module KernelCompiler

using Core.Compiler
using Core.Compiler: MethodInstance, NativeInterpreter, CodeInfo, CodeInstance, WorldView, OptimizationState
using Base.Meta

import LLVM

include("codecache.jl")
const CACHE = Dict{DataType, CodeCache}()
get_cache(ai::DataType) = get!(CodeCache, CACHE, ai)

include("kernelinterpreter.jl")
include("optimize.jl")
include("codegen.jl")

end # module
