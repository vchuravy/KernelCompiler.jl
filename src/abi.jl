"""
    call(f, args...) -> result

Compile (if needed) and call function `f` with the given arguments.
"""
@inline function call(f, args...)
    argtypes = Tuple{map(Core.Typeof, args)...}
    rettyp = Base.infer_return_type(f, argtypes)
    _call_impl(rettyp, f, args...)
end
@generated function _call_impl(::Type{R}, f, args::Vararg{Any,N}) where {R,N}
    argtypes = Tuple{args...}

    # Build tuple expression for ccall: (T1, T2, ...)
    ccall_types = Expr(:tuple)
    for i in 1:N
        push!(ccall_types.args, args[i])
    end

    # Build argument expressions
    argexprs = Expr[]
    for i in 1:N
        push!(argexprs, :(args[$i]))
    end

    quote
        world = get_world_counter()
        mi = @something(method_instance(f, $argtypes; world, method_table=CUSTOM_MT),
                        method_instance(f, $argtypes; world),
                        throw(MethodError(f, $argtypes)))

        cache = CacheView{NativeResults}(:NativeExample, world)
        ptr = compile!(cache, mi)
        ccall(ptr, R, $ccall_types, $(argexprs...))
    end
end