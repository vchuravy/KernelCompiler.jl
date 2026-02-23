module KernelCompiler

using CompilerCaching
using CompilerCaching: get_source, get_codeinfos
using LLVM
using LLVM.Interop
import Compiler as CC

using Base: get_world_counter, CodegenParams

include("simt_pass.jl")
include("codegen.jl")

## high-level API

function compile!(cache::CacheView, mi::Core.MethodInstance)
    # Get a CI through inference
    ci = get(cache, mi, nothing)
    if ci === nothing
        interp = CustomInterpreter(cache)
        CompilerCaching.typeinf!(cache, interp, mi)
        ci = get(cache, mi)
    end

    # Check for a cache hit
    res = results(cache, ci)
    if res.executable !== nothing
        return res.executable
    end

    # emit code: generate LLVM IR
    if res.code === nothing
        res.code = julia_codegen(cache, mi, ci)
    end

    # emit executable: JIT compile to function pointer
    if res.executable === nothing
        res.executable = julia_jit(cache, mi, res.code)
    end

    return res.executable
end

function compile!(cache::CacheView, mi::Core.MethodInstance, argtypes::Vector{Any})
    ci = get(cache, mi, nothing)
    if ci === nothing
        interp = CustomInterpreter(cache)
        CompilerCaching.typeinf!(cache, interp, mi)
        ci = get(cache, mi)
    end

    # Ensure const-seeded inference has run
    if CompilerCaching.get_source(ci, argtypes) === nothing
        interp = CustomInterpreter(cache)
        CompilerCaching.typeinf!(cache, interp, mi, argtypes)
    end

    # codegen + JIT using const-optimized source
    code = julia_codegen(cache, mi, ci; argtypes)
    return julia_jit(cache, mi, code)
end

include("abi.jl")

function barrier()
    ccall("extern julia.kernel.barrier", llvmcall, Cvoid, ())
end


end # module KernelCompiler
