import GPUCompiler
import GPUCompiler: FunctionSpec

function resolver(name, ctx)
    name = unsafe_string(name)
    ## Step 0: Should have already resolved it iff it was in the
    ##         same module
    ## Step 1: See if it's something known to the execution engine
    ptr = C_NULL
    if ctx != C_NULL
        orc = OrcJIT(ctx)
        ptr = pointer(address(orc, name))
    end

    ## Step 2: Search the program symbols
    if ptr == C_NULL
        #
        # SearchForAddressOfSymbol expects an unmangled 'C' symbol name.
        # Iff we are on Darwin, strip the leading '_' off.
        @static if Sys.isapple()
            if name[1] == '_'
                name = name[2:end]
            end
        end
        # ptr = LLVM.find_symbol(name)
        ptr = LLVM.API.LLVMSearchForAddressOfSymbol(name)
    end

    ## Step 4: Lookup in libatomic
    # TODO: Do we need to do this?

    if ptr == C_NULL
        error("OrcJIT: Symbol `$name` lookup failed. Aborting!")
    end

    return UInt64(reinterpret(UInt, ptr))
end

struct Entry
    specfunc::Ptr{Cvoid}
    func::Ptr{Cvoid}
end

# const compiled_cache = Dict{UInt, Any}()

function jit(f::F,tt::TT=Tuple{}) where {F<:Core.Function, TT<:Type}
    fspec = FunctionSpec(f, tt, #=kernel=# false, #=name=# nothing)
    GPUCompiler.cached_compilation(_jit, fspec)::Entry
    #  GPUCompiler.cached_compilation(compiled_cache, _jit, _link, fspec)::Entry
end

# function _link(@nospecialize(fspec::FunctionSpec), entry)
#     return entry
# end

# actual compilation
function _jit(@nospecialize(fspec::FunctionSpec))
    llvm_specfunc, llvm_func, llvm_mod = codegen(fspec.f, fspec.tt)

    specfunc_name = LLVM.name(llvm_specfunc)
    func_name = LLVM.name(llvm_func)

    # set linkage to extern visible
    # otherwise `addressin` won't find them
    linkage!(llvm_func, LLVM.API.LLVMExternalLinkage)
    linkage!(llvm_specfunc, LLVM.API.LLVMExternalLinkage)

    run_pipeline!(llvm_mod)

    # Now invoke the JIT
    jitted_mod = compile!(orc[], llvm_mod, @cfunction(resolver, UInt64, (Cstring, Ptr{Cvoid})), orc[])

    specfunc_addr = addressin(orc[], jitted_mod, specfunc_name)
    specfunc_ptr  = pointer(specfunc_addr)

    func_addr = addressin(orc[], jitted_mod, func_name)
    func_ptr  = pointer(func_addr)

    if  specfunc_ptr === C_NULL || func_ptr === C_NULL
        @error "Compilation error" fspec specfunc_ptr func_ptr
    end

    return Entry(specfunc_ptr, func_ptr)
end

