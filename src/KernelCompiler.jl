module KernelCompiler

include("kernelinterpreter.jl")
include("optimize.jl")

struct Kernel{Ctx, F}
    ctx::Ctx
    f::F
end
function (kernel::Kernel)(args...)
    Base.invoke_within(KernelC(), kernel, args...)
end

include("transform.jl")
include("intrinsics.jl")



end # module
