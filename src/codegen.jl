#==============================================================================#
# Native Code Emission
#==============================================================================#

# LLVM context helper
function with_llvm_context(f)
    ts_ctx = ThreadSafeContext()
    ctx = context(ts_ctx)
    activate(ctx)
    try
        f(ctx)
    finally
        deactivate(ctx)
        dispose(ts_ctx)
    end
end

# Callback function for codegen to look in the cache
const _codegen_cache = Ref{Any}(nothing)
function _codegen_lookup_cb(mi, min_world, max_world)
    # Create a cache at the min_world for lookup
    cache = _codegen_cache[]
    lookup_cache = CacheView{typeof(cache).parameters[1], typeof(cache).parameters[2]}(cache.owner, min_world)
    ci = get(lookup_cache, mi, nothing)
    @static if VERSION < v"1.12.0-DEV.1434"
        # Refuse to return CI without source - force re-inference before codegen
        if ci !== nothing && ci.inferred === nothing
            return nothing
        end
    end
    return ci
end

# Global JuliaOJIT instance
const global_jljit = Ref{Any}(nothing)
function getglobal_jljit()
    if global_jljit[] === nothing
        jljit = JuliaOJIT()
        # Add process symbol generator so Julia runtime symbols can be resolved
        jd = JITDylib(jljit)
        prefix = LLVM.get_prefix(jljit)
        dg = LLVM.CreateDynamicLibrarySearchGeneratorForProcess(prefix)
        add!(jd, dg)
        global_jljit[] = jljit
    end
    return global_jljit[]
end

"""
    julia_codegen(cache, mi, ci; argtypes=nothing, dump_llvm=false, dump_module=false)
        -> (ir_bytes, entry_name, llvm_ir)

Generate LLVM IR and return serializable intermediate result.
Returns a tuple of (LLVM bitcode bytes, entry function name, LLVM IR text).
The `llvm_ir` string is empty unless `dump_llvm` or `dump_module` is set.
When `dump_llvm` is true, returns the IR of just the entry function.
When `dump_module` is true, returns the IR of the entire module.

Uses `get_codeinfos(ci)` to collect CodeInfos by walking :invoke statements (1.12+)
or cache lookup callback (1.11). When `argtypes` is provided, uses the const-optimized
source for the root CI via `get_codeinfos(ci, argtypes)`.

This function handles codegen but does not JIT compile - use `julia_jit` for that.
"""
function julia_codegen(cache::CacheView, mi::Core.MethodInstance,
                       ci::Core.CodeInstance;
                       argtypes::Union{Vector{Any},Nothing}=nothing,
                       dump_llvm::Bool=false,
                       dump_module::Bool=false)
    # Set up globals for the lookup callback
    _codegen_cache[] = cache
    lookup_cfunction = @cfunction(_codegen_lookup_cb, Any, (Any, UInt, UInt))

    # Set up codegen parameters
    @static if VERSION < v"1.12.0-DEV.1667"
        params = CodegenParams(; lookup = Base.unsafe_convert(Ptr{Nothing}, lookup_cfunction))
    else
        params = CodegenParams()
    end

    # Get JuliaOJIT for target configuration
    jljit = getglobal_jljit()

    # Generate LLVM IR
    with_llvm_context() do ctx
        # Create LLVM module
        ts_mod = ThreadSafeModule("native_compile")

        # Configure module for native target using JuliaOJIT's settings
        ts_mod() do mod
            triple!(mod, triple(jljit))
            datalayout!(mod, datalayout(jljit))
        end

        # Generate native code
        @static if VERSION >= v"1.12.0-DEV.1823"
            cis_vec = Any[]
            codeinfos = argtypes !== nothing ? get_codeinfos(ci, argtypes) : get_codeinfos(ci)
            for (ci, src) in codeinfos
                push!(cis_vec, ci)
                push!(cis_vec, src)
            end
            native_code = @ccall jl_emit_native(
                cis_vec::Vector{Any},
                ts_mod::LLVM.API.LLVMOrcThreadSafeModuleRef,
                Ref(params)::Ptr{CodegenParams},
                false::Cint
            )::Ptr{Cvoid}
        elseif VERSION >= v"1.12.0-DEV.1667"
            native_code = @ccall jl_create_native(
                [mi]::Vector{Core.MethodInstance},
                ts_mod::LLVM.API.LLVMOrcThreadSafeModuleRef,
                Ref(params)::Ptr{CodegenParams},
                1::Cint, 0::Cint, 0::Cint, cache.world::Csize_t,
                lookup_cfunction::Ptr{Cvoid}
            )::Ptr{Cvoid}
        else
            # On 1.11, jl_create_native reads ci.inferred via the lookup callback.
            # Temporarily swap with the const-seeded source if available.
            saved_inferred = nothing
            if argtypes !== nothing
                const_src = get_source(ci, argtypes)
                if const_src !== nothing
                    saved_inferred = @atomic :monotonic ci.inferred
                    @atomic :monotonic ci.inferred = const_src
                end
            end
            native_code = C_NULL
            try
                native_code = @ccall jl_create_native(
                    [mi]::Vector{Core.MethodInstance},
                    ts_mod::LLVM.API.LLVMOrcThreadSafeModuleRef,
                    Ref(params)::Ptr{CodegenParams},
                    1::Cint, 0::Cint, 0::Cint, cache.world::Csize_t
                )::Ptr{Cvoid}
            finally
                if saved_inferred !== nothing
                    @atomic :monotonic ci.inferred = saved_inferred
                end
            end
        end

        @assert native_code != C_NULL "Code generation failed"

        # Get the ThreadSafeModule
        llvm_mod_ref = @ccall jl_get_llvm_module(
                native_code::Ptr{Cvoid}
            )::LLVM.API.LLVMOrcThreadSafeModuleRef
        @assert llvm_mod_ref != C_NULL "Failed to get LLVM module"

        llvm_ts_mod = ThreadSafeModule(llvm_mod_ref)

        # Get function name from CodeInstance
        ci = get(cache, mi, nothing)
        @assert ci !== nothing "CodeInstance not found after codegen"

        func_idx = Ref{Int32}(-1)
        specfunc_idx = Ref{Int32}(-1)
        @ccall jl_get_function_id(native_code::Ptr{Cvoid}, ci::Any,
               func_idx::Ptr{Int32}, specfunc_idx::Ptr{Int32})::Nothing

        func_name = nothing
        if specfunc_idx[] >= 1
            func_ref = @ccall jl_get_llvm_function(
                    native_code::Ptr{Cvoid},
                    (specfunc_idx[] - 1)::UInt32
                )::LLVM.API.LLVMValueRef
            @assert func_ref != C_NULL
            func_name = name(LLVM.Function(func_ref))
        elseif func_idx[] >= 1
            func_ref = @ccall jl_get_llvm_function(
                    native_code::Ptr{Cvoid},
                    (func_idx[] - 1)::UInt32
                )::LLVM.API.LLVMValueRef
            @assert func_ref != C_NULL
            func_name = name(LLVM.Function(func_ref))
        end

        @assert func_name !== nothing "No compiled function found"

        # Capture LLVM IR text if requested
        llvm_ir = if dump_module
            llvm_ts_mod() do mod
                string(mod)
            end
        elseif dump_llvm
            llvm_ts_mod() do mod
                string(functions(mod)[func_name])
            end
        else
            ""
        end

        # Serialize to bitcode
        ir_bytes = llvm_ts_mod() do mod
            convert(Vector{UInt8}, mod)
        end

        return (ir_bytes, func_name, llvm_ir)
    end
end

"""
    julia_jit(cache, mi, ir_data) -> Ptr{Cvoid}

JIT compile LLVM bitcode to a function pointer.

Takes a tuple of (LLVM bitcode bytes, entry function name) as returned by `julia_codegen`.
The `cache` and `mi` arguments are ignored but included for use as an `emit_executable` callback.
"""
function julia_jit(cache, mi, ir_data)
    ir_bytes, entry_name = ir_data

    jljit = getglobal_jljit()
    jd = JITDylib(jljit)

    with_llvm_context() do ctx
        # Parse bitcode back into a module, then wrap in ThreadSafeModule
        mod = parse(LLVM.Module, ir_bytes)
        ts_mod = ThreadSafeModule(mod)

        # Run Julia's optimization pipeline to lower intrinsics
        ts_mod() do m
            run!(SIMTModulePass(), m)
            run!(JuliaPipeline(), m)
        end

        # Add to JIT
        add!(jljit, jd, ts_mod)

        # Look up the compiled function
        addr = LLVM.lookup(jljit, entry_name)
        return pointer(addr)
    end
end