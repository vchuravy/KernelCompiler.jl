import GPUCompiler
import GPUCompiler: FunctionSpec

struct Entry{F, TT}
    f::F
    specfunc::Ptr{Cvoid}
    func::Ptr{Cvoid}
end

# Slow ABI
function __call(entry::Entry{F, TT}, args::TT) where {F, TT} 
    args = Any[args...]
    ccall(entry.func, Any, (Any, Ptr{Any}, Int32), entry.f, args, length(args))
end

(entry::Entry)(args...) = __call(entry, args)

const compiled_cache = Dict{UInt, Any}()

function jit(f::F,tt::TT=Tuple{}) where {F, TT<:Type}
    fspec = FunctionSpec(f, tt, #=kernel=# false, #=name=# nothing)
    GPUCompiler.cached_compilation(compiled_cache, _jit, _link, fspec)::Entry{F, tt}
end

function _link(@nospecialize(fspec::FunctionSpec), (llvm_mod, func_name, specfunc_name))
    # Now invoke the JIT
    jitted_mod = compile!(orc[], llvm_mod)

    specfunc_addr = addressin(orc[], jitted_mod, specfunc_name)
    specfunc_ptr  = pointer(specfunc_addr)

    func_addr = addressin(orc[], jitted_mod, func_name)
    func_ptr  = pointer(func_addr)

    if  specfunc_ptr === C_NULL || func_ptr === C_NULL
        @error "Compilation error" fspec specfunc_ptr func_ptr
    end

    return Entry{typeof(fspec.f), fspec.tt}(fspec.f, specfunc_ptr, func_ptr)
end

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

    return (llvm_mod, func_name, specfunc_name)
end

