module KernelCompiler

using Core.Compiler
using Core.Compiler: MethodInstance, NativeInterpreter, CodeInfo, CodeInstance, WorldView, OptimizationState
using Base.Meta

using LLVM
using LLVM.Interop

include("codecache.jl")
const CACHE = Dict{DataType, CodeCache}()
get_cache(ai::DataType) = CACHE[ai]

include("kernelinterpreter.jl")
include("optimize.jl")
include("codegen.jl")

# We have one global JIT and TM
const orc = Ref{LLVM.OrcJIT}()
const tm  = Ref{LLVM.TargetMachine}()

function __init__()
    CACHE[NativeInterpreter] = CodeCache(cpu_invalidate)

    opt_level = Base.JLOptions().opt_level
    if opt_level < 2
        optlevel = LLVM.API.LLVMCodeGenLevelNone
    elseif opt_level == 2
        optlevel = LLVM.API.LLVMCodeGenLevelDefault
    else
        optlevel = LLVM.API.LLVMCodeGenLevelAggressive
    end

    tm[] = LLVM.JITTargetMachine(optlevel=optlevel)
    LLVM.asm_verbosity!(tm[], true)

    orc[] = LLVM.OrcJIT(tm[]) # takes ownership of tm
    atexit() do
        LLVM.dispose(orc[])
    end
end

include("pipeline.jl")
include("jit.jl")

end # module
