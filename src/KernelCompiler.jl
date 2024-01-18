module KernelCompiler

include("kernelinterpreter.jl")
include("optimize.jl")

struct Kernel{F}
    f::F
end
function (kernel::Kernel{F})(args...) where F
    Base.invoke_within(KernelC(), kernel.f, args...)
end

end # module
