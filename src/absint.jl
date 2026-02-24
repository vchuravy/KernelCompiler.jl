using Base: get_world_counter

using Base.Experimental: @MethodTable, @overlay
@MethodTable CUSTOM_MT


## Results struct for native compilation

mutable struct NativeResults
    code::Any         # (ir_bytes, entry_name) from julia_codegen
    executable::Any   # Ptr{Cvoid} from julia_jit
    NativeResults() = new(nothing, nothing)
end


## abstract interpreter

const InfCacheT = @static if isdefined(CC, :InferenceCache)
    CC.InferenceCache
else
    Vector{CC.InferenceResult}
end

struct CustomInterpreter <: CC.AbstractInterpreter
    world::UInt
    cache::CacheView
    method_table::CC.OverlayMethodTable
    inf_cache::InfCacheT
    inf_params::CC.InferenceParams
    opt_params::CC.OptimizationParams

    function CustomInterpreter(cache::CacheView)
        @assert cache.world <= get_world_counter()
        new(cache.world, cache,
            CC.OverlayMethodTable(cache.world, CUSTOM_MT),
            InfCacheT(),
            CC.InferenceParams(),
            CC.OptimizationParams()
        )
    end
end

# required AbstractInterpreter interface implementation
CC.InferenceParams(interp::CustomInterpreter) = interp.inf_params
CC.OptimizationParams(interp::CustomInterpreter) = interp.opt_params
CC.get_inference_cache(interp::CustomInterpreter) = interp.inf_cache
@static if isdefined(CC, :get_inference_world)
    CC.get_inference_world(interp::CustomInterpreter) = interp.world
else
    CC.get_world_counter(interp::CustomInterpreter) = interp.world
end
CC.lock_mi_inference(::CustomInterpreter, ::Core.MethodInstance) = nothing
CC.unlock_mi_inference(::CustomInterpreter, ::Core.MethodInstance) = nothing

# Use overlay method table for method lookup during inference
CC.method_table(interp::CustomInterpreter) = interp.method_table

# integration with CompilerCaching.jl
@setup_caching CustomInterpreter.cache
