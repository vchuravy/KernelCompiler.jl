### interpreter
import Core.Compiler: AbstractInterpreter, InferenceResult, InferenceParams, InferenceState, OptimizationParams
import Core.Compiler: get_world_counter, get_inference_cache, code_cache, lock_mi_inference, unlock_mi_inference

struct KernelInterpreter{Inner<:AbstractInterpreter} <: AbstractInterpreter
    # Wrapped AbstractInterpreter
    inner::Inner
end
KernelInterpreter(interp) = KernelInterpreter(interp)

# Quickly and easily satisfy the AbstractInterpreter API contract
get_world_counter(ki::KernelInterpreter) =  get_world_counter(ki.inner)
get_inference_cache(ki::KernelInterpreter) = get_inference_cache(ki.inner) 
InferenceParams(ki::KernelInterpreter) = InferenceParams(ki.inner)
OptimizationParams(ki::KernelInterpreter) = OptimizationParams(ki.inner)
Core.Compiler.may_optimize(ni::KernelInterpreter) = true # TODO: Forward?
Core.Compiler.may_compress(ni::KernelInterpreter) = true # TODO: Forward?
Core.Compiler.may_discard_trees(ni::KernelInterpreter) = true # TODO: Forward?
Core.Compiler.add_remark!(ni::KernelInterpreter, sv::InferenceState, msg) = Core.Compiler.add_remark!(ni.inner, sv, msg)

### codegen/interence integration
code_cache(ki::KernelInterpreter) = WorldView(get_cache(typeof(ki.inner)), get_world_counter(ki))

# No need to do any locking since we're not putting our results into the runtime cache
lock_mi_inference(ki::KernelInterpreter, mi::MethodInstance) = nothing
unlock_mi_inference(ki::KernelInterpreter, mi::MethodInstance) = nothing

function cpu_invalidate(replaced, max_world)
    cache = get_cache(NativeInterpreter)
    invalidate(cache, replaced, max_world, 0)
    return nothing
end

function cpu_cache_lookup(mi, min_world, max_world)
    wvc = WorldView(get_cache(NativeInterpreter), min_world, max_world)
    return Core.Compiler.get(wvc, mi, nothing)
end

function cpu_infer(mi, min_world, max_world)
    wvc = WorldView(get_cache(NativeInterpreter), min_world, max_world)
    interp = KernelInterpreter(NativeInterpreter(min_world))
    return infer(wvc, mi, interp)
end

function infer(wvc, mi, interp)
    src = Core.Compiler.typeinf_ext_toplevel(interp, mi)
    # inference populates the cache, so we don't need to jl_get_method_inferred
    @assert Core.Compiler.haskey(wvc, mi)

    # if src is rettyp_const, the codeinfo won't cache ci.inferred
    # (because it is normally not supposed to be used ever again).
    # to avoid the need to re-infer, set that field here.
    # This is required for being able to use `cache_lookup` as the lookup
    # function for `CodegenParams` and `jl_create_native`.
    ci = Core.Compiler.getindex(wvc, mi)
    if ci !== nothing && ci.inferred === nothing
        ci.inferred = src
    end
    return
end
