module KernelCompiler

include("kernelinterpreter.jl")
include("optimize.jl")

struct Kernel{Ctx, F}
    ctx::Ctx
    f::F
end
function (kernel::Kernel)(args...)
    @with Context => kernel.ctx begin
        Base.invoke_within(KernelC{typeof(kernel.ctx)}(), kernel.f, args...)
    end
end

include("transform.jl")
include("intrinsics.jl")



end # module
