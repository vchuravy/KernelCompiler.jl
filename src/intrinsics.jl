struct KernelFunction{Ctx, Name}
    ctx::Ctx
end
Base.nameof(::KernelFunction{C, Name}) where {C, Name} = Name

# KerneIntrinsics are only valid within a KernelFunction
abstract type KernelIntrinsic end

struct WorkgroupIndex <: KernelIntrinsic end
const workgroupindex = WorkgroupIndex()
# Opaque intrinsic
@noinline function (::WorkgroupIndex)(::KernelFunction)
    Base.inferencebarrier(nothing)::Int # TODO: calculate index type from workgroupsize
end

struct Synchronize <: KernelIntrinsic end
const synchronize = Synchronize()
# Opaque intrinsic
@noinline function (::Synchronize)(::KernelFunction)
    Base.inferencebarrier(nothing)::Nothing
end


struct WorkgroupSize <: KernelIntrinsic end
const workgroupsize = WorkgroupSize()
(::WorkgroupSize)(kernel::KernelFunction) = kernel.ctx

## Mock GPU
# @inline function (::WorkgroupIndex)(kf::KernelFunction{<:CUDA})
#     lidx = threadIdx.x()
#     CartesianIndices(workgroupsize(kf))[lidx]
# end

## Mock CPU groupindex
#  @inline function (::GroupIndex)(kf::KernelFunction{<:CPU})
#    task_local_storage(:kernel_group)::Int
# end