### interpreter
const CC = Core.Compiler

import .CC: SSAValue, GlobalRef

struct KernelC <: CC.AbstractCompiler end
CC.abstract_interpreter(::KernelC, world::UInt) =
    KernelCompilerInterp(; world)

struct KernelCompilerInterp <: CC.AbstractInterpreter
    world::UInt
    inf_params::CC.InferenceParams
    opt_params::CC.OptimizationParams
    inf_cache::Vector{CC.InferenceResult}
    code_cache::CC.InternalCodeCache
    compiler::KernelC
    function KernelCompilerInterp(;
                world::UInt = Base.get_world_counter(),
                compiler::KernelC = KernelC(),
                inf_params::CC.InferenceParams = CC.InferenceParams(),
                opt_params::CC.OptimizationParams = CC.OptimizationParams(),
                inf_cache::Vector{CC.InferenceResult} = CC.InferenceResult[],
                code_cache::CC.InternalCodeCache = CC.InternalCodeCache(compiler))
        return new(world, inf_params, opt_params, inf_cache, code_cache, compiler)
    end
end

CC.InferenceParams(interp::KernelCompilerInterp) = interp.inf_params
CC.OptimizationParams(interp::KernelCompilerInterp) = interp.opt_params
CC.get_world_counter(interp::KernelCompilerInterp) = interp.world
CC.get_inference_cache(interp::KernelCompilerInterp) = interp.inf_cache
CC.code_cache(interp::KernelCompilerInterp) = CC.WorldView(interp.code_cache, CC.WorldRange(interp.world))
CC.cache_owner(interp::KernelCompilerInterp) = interp.compiler

import Core.Compiler: retrieve_code_info, maybe_validate_code

# Replace usage sited of `retrieve_code_info`, OptimizationState is one such, but in all interesting use-cases
# it is derived from an InferenceState. There is a third one in `typeinf_ext` in case the module forbids inference.
function CC.InferenceState(result::CC.InferenceResult, cache_mode::UInt8, interp::KernelCompilerInterp)
    world = CC.get_world_counter(interp)
    src = retrieve_code_info(result.linfo, world)
    src === nothing && return nothing
    maybe_validate_code(result.linfo, src, "lowered")
    # src = transform(interp, result.linfo, src)
    # maybe_validate_code(result.linfo, src, "transformed")
    return CC.InferenceState(result, src, cache_mode, interp)
end