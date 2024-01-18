# Allows for Cassette Pass transforms 

function static_eval(mod, name)
    if Base.isbindingresolved(mod, name) && Base.isdefined(mod, name)
        return getfield(mod, name)
    else
        return nothing
    end
end

function transform(interp, mi, src)
    method = mi.def
    f = static_eval(method.module, method.name)
    # TODO check if src contains calls to kernel intrinsics
    # TODO: We need a way of disabling transformations at a barrier
    if f isa KernelIntrinsic || f === __context__
        return src
    else
        needs_transform = Ref(false)
        visit_calls(src) do ff, _, _
            if ff isa KernelIntrinsic
                needs_transform[] = true
            end
        end
        if needs_transform[]
            src = copy(src)
            kernel_transform!(interp, mi, src)
            return src
        end
    end 
    return src
end

function ir_element(x, code::Vector)
    while isa(x, Core.SSAValue)
        x = code[x.id]
    end
    return x
end

"""
```
is_ir_element(x, y, code::Vector)
```
Return `true` if `x === y` or if `x` is an `SSAValue` such that
`is_ir_element(code[x.id], y, code)` is `true`.
See also: [`replace_match!`](@ref), [`insert_statements!`](@ref)
"""
function is_ir_element(x, y, code::Vector)
    result = false
    while true # break by default
        if x === y #
            result = true
            break
        elseif isa(x, Core.SSAValue)
            x = code[x.id]
        else
            break
        end
    end
    return result
end

"""
    insert_statements!(code::Vector, codelocs::Vector, stmtcount, newstmts)


For every statement `stmt` at position `i` in `code` for which `stmtcount(stmt, i)` returns
an `Int`, remove `stmt`, and in its place, insert the statements returned by
`newstmts(stmt, i)`. If `stmtcount(stmt, i)` returns `nothing`, leave `stmt` alone.

For every insertion, all downstream `SSAValue`s, label indices, etc. are incremented
appropriately according to number of inserted statements.

Proper usage of this function dictates that following properties hold true:

- `code` is expected to be a valid value for the `code` field of a `CodeInfo` object.
- `codelocs` is expected to be a valid value for the `codelocs` field of a `CodeInfo` object.
- `newstmts(stmt, i)` should return a `Vector` of valid IR statements.
- `stmtcount` and `newstmts` must obey `stmtcount(stmt, i) == length(newstmts(stmt, i))` if
    `isa(stmtcount(stmt, i), Int)`.

To gain a mental model for this function's behavior, consider the following scenario. Let's
say our `code` object contains several statements:
code = Any[oldstmt1, oldstmt2, oldstmt3, oldstmt4, oldstmt5, oldstmt6]
codelocs = Int[1, 2, 3, 4, 5, 6]

Let's also say that for our `stmtcount` returns `2` for `stmtcount(oldstmt2, 2)`, returns `3`
for `stmtcount(oldstmt5, 5)`, and returns `nothing` for all other inputs. From this setup, we
can think of `code`/`codelocs` being modified in the following manner:
newstmts2 = newstmts(oldstmt2, 2)
newstmts5 = newstmts(oldstmt5, 5)
code = Any[oldstmt1,
           newstmts2[1], newstmts2[2],
           oldstmt3, oldstmt4,
           newstmts5[1], newstmts5[2], newstmts5[3],
           oldstmt6]
codelocs = Int[1, 2, 2, 3, 4, 5, 5, 5, 6]

See also: [`replace_match!`](@ref), [`is_ir_element`](@ref)
"""
function insert_statements!(code, codelocs, ssaflags, stmtcount, newstmts)
    ssachangemap = fill(0, length(code))
    labelchangemap = fill(0, length(code))
    worklist = Tuple{Int,Int}[]
    for i in 1:length(code)
        stmt = code[i]
        nstmts = stmtcount(stmt, i)
        if nstmts !== nothing
            addedstmts = nstmts - 1
            push!(worklist, (i, addedstmts))
            ssachangemap[i] = addedstmts
            if i < length(code)
                labelchangemap[i + 1] = addedstmts
            end
        end
    end
    Core.Compiler.renumber_ir_elements!(code, ssachangemap, labelchangemap)
    for (i, addedstmts) in worklist
        i += ssachangemap[i] - addedstmts # correct the index for accumulated offsets
        stmts = newstmts(code[i], i)
        @assert length(stmts) == (addedstmts + 1)
        code[i] = stmts[end]
        for j in 1:(length(stmts) - 1) # insert in reverse to maintain the provided ordering
            insert!(code, i, stmts[end - j])
            insert!(codelocs, i, codelocs[i])
            insert!(ssaflags, i, 0x00)
        end
    end
end

function visit_calls(visitor, src)
    for (i, x) in enumerate(src.code)
        stmt = Base.Meta.isexpr(x, :(=)) ? x.args[2] : x
        if Base.Meta.isexpr(stmt, :call)
            applycall = is_ir_element(stmt.args[1], GlobalRef(Core, :_apply), src.code) 
            applyitercall = is_ir_element(stmt.args[1], GlobalRef(Core, :_apply_iterate), src.code) 
            if applycall
                fidx = 2
            elseif applyitercall
                fidx = 3
            else
                fidx = 1
            end
            f = stmt.args[fidx]
            f = ir_element(f, src.code)
            if f isa GlobalRef
                ff = static_eval(f.mod, f.name)
                if ff !== nothing
                    visitor(ff, stmt, fidx)
                end
            end
        end
    end
end

function kernel_transform!(interp, mi, src)
    # 1. Insert __context__ 
    stmtcount = (x, i) -> i == 1 ? 3 : nothing
    newstmts = (x, i) -> begin
        @assert i == 1
        stmts = [
            Expr(:call, GlobalRef(Core, :_call_within), nothing, GlobalRef(@__MODULE__, :__context__)) # URGH
            Expr(:call, GlobalRef(Core, :typeassert), Core.SSAValue(1), context_type(interp.compiler))
            x
        ]
        return stmts
    end

    # 2. Splice __context__ into all intrinsics
    insert_statements!(src.code, src.codelocs, src.ssaflags, stmtcount, newstmts)
    visit_calls(src) do ff, stmt, fidx
        if ff isa KernelIntrinsic
            insert!(stmt.args, fidx+1, Core.SSAValue(2))
        end
    end
    src.ssavaluetypes = length(src.code)
end