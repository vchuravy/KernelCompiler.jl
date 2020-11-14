struct KernelFunction{Ctx, Name}
    ctx::Ctx
end
Base.nameof(::KernelFunction{C, Name}) where {C, Name} = Name

abstract type KernelIntrinsic  end

struct WorkgroupIndex <: KernelIntrinsic end

struct WorkgroupSize <: KernelIntrinsic end

(::WorkgroupSize)(kernel::KernelFunction) = kernel.ctx
const workgroupsize = WorkgroupSize()

