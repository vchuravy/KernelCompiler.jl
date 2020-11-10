### Cache
struct CodeCache
    dict::Dict{MethodInstance,Vector{CodeInstance}}
    callback::Function
    CodeCache(callback) = new(Dict{MethodInstance,Vector{CodeInstance}}(), callback)
end

function Core.Compiler.setindex!(cache::CodeCache, ci::CodeInstance, mi::MethodInstance)
    if !isdefined(mi, :callbacks)
        mi.callbacks = Any[cache.callback]
    else
        # Check if callback is present
        if all(cb -> cb !== cache.callback, mi.callbacks)
            push!(mi.callbacks, cache.callback)
        end
    end

    cis = get!(cache.dict, mi, CodeInstance[])
    push!(cis, ci)
end

### world view of the cache

using Core.Compiler: WorldView

function Core.Compiler.haskey(wvc::WorldView{CodeCache}, mi::MethodInstance)
    Core.Compiler.get(wvc, mi, nothing) !== nothing
end

function Core.Compiler.get(wvc::WorldView{CodeCache}, mi::MethodInstance, default)
    cache = wvc.cache
    for ci in get!(cache.dict, mi, CodeInstance[])
        if ci.min_world <= wvc.worlds.min_world && wvc.worlds.max_world <= ci.max_world
            # TODO: if (code && (code == jl_nothing || jl_ir_flag_inferred((jl_array_t*)code)))
            return ci
        end
    end

    return default
end

function Core.Compiler.getindex(wvc::WorldView{CodeCache}, mi::MethodInstance)
    r = Core.Compiler.get(wvc, mi, nothing)
    r === nothing && throw(KeyError(mi))
    return r::CodeInstance
end

Core.Compiler.setindex!(wvc::WorldView{CodeCache}, ci::CodeInstance, mi::MethodInstance) =
    Core.Compiler.setindex!(wvc.cache, ci, mi)

# invalidation
# invalidate_method_instance, but for our cache
function invalidate(cache::CodeCache, replaced::MethodInstance, max_world, depth)
    cis = get(cache.dict, replaced, nothing)
    if cis === nothing
        return
    end
    for ci in cis
        if ci.max_world == ~0 % Csize_t
            @assert ci.min_world - 1 <= max_world "attempting to set illogical constraints"
            ci.max_world = max_world
        end
        @assert ci.max_world <= max_world
    end

    # recurse to all backedges to update their valid range also
    if isdefined(replaced, :backedges)
        backedges = replaced.backedges
        # Don't empty backedges `invalidate_method_instance` in C will do that later
        # replaced.backedges = Any[]

        for mi in backedges
            invalidate(cache, mi, max_world, depth + 1)
        end
    end
end

function invalidate_backedges(cache::CodeCache, replaced::MethodInstance, max_world)
    # TODO: Julia proper does not invalidate the world-ages for `replaced`
    #       I assume that is handled by the method table invalidations.
    #       For now we invalidate the root as well

    ## original definition:
    # if isdefined(replaced, :backedges)
    #     backedges = replaced.backedges
    #     # Don't empty backedges `invalidate_backedges` in C will do that later
    #     # replaced.backedges = Any[]

    #     for mi in backedges
    #         invalidate(cache, mi, max_world, 1)
    #     end
    # end
    invalidate(cache, replaced, max_world, 0)
end
