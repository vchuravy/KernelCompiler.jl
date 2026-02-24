function simt_module_pass! end
SIMTModulePass() = NewPMModulePass("simt_module_pass", simt_module_pass!);

# 1. Discover callgraph that uses intrinsics "julia.kernel.*"
function simt_module_pass!(mod::LLVM.Module)

    intrinsics = Set{LLVM.Function}()

    # find intrinsics "julia.kernel.*"
    for func in functions(mod)
        name = string(LLVM.name(func))
        if startswith(name, "julia.kernel.")
            push!(intrinsics, func)
        end
    end

    worklist = collect(intrinsics)
    visited = Set{LLVM.Function}()

    while !isempty(worklist)
        func = pop!(worklist)
        if func in visited
            continue
        end
        push!(visited, func)

        # Add callers to worklist
        for inst in uses(func)
            caller = parent(parent(inst))
            if caller ∉ visited
                push!(worklist, caller)
            end
        end
    end

    # Set always_inline on all visited functions
    for func in visited
        if func in intrinsics
            continue
        end
        push!(function_attributes(func), EnumAttribute("alwaysinline"))
    end

    run!(AlwaysInlinerPass(), mod)

    return true
end

