# KerneIntrinsics are only valid within a KernelFunction
abstract type KernelIntrinsic end

struct Context <: KernelIntrinsic end
const __context__ = Context()
(::Context)(kernel::Kernel{Ctx}) where Ctx = kernel.ctx


# struct WorkgroupIndex <: KernelIntrinsic end
# const workgroupindex = WorkgroupIndex()
# # Opaque intrinsic
# @noinline function (::WorkgroupIndex)(::KernelFunction)
#     Base.inferencebarrier(nothing)::Int # TODO: calculate index type from workgroupsize
# end

# struct Synchronize <: KernelIntrinsic end
# const synchronize = Synchronize()
# # Opaque intrinsic
# @noinline function (::Synchronize)(::KernelFunction)
#     Base.inferencebarrier(nothing)::Nothing
# end


