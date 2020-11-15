using KernelCompiler
using Test

# Can't run inside a testset :/
parent(x) = child(x)
child(x) = x+1

thunk1 = KernelCompiler.jit(parent, Tuple{Int})
@test thunk1 == KernelCompiler.jit(parent, Tuple{Int})

@test thunk1(2) == 3
child(x) = x+2

thunk2 = KernelCompiler.jit(parent, Tuple{Int})
@test thunk1 != thunk2
@test thunk2(2) == 4

parent() = child()
child() = 3

thunk1 = KernelCompiler.jit(parent, Tuple{})
@test thunk1 == KernelCompiler.jit(parent, Tuple{})

@test thunk1() == 3
child() = 4

thunk2 = KernelCompiler.jit(parent, Tuple{})
@test thunk1 != thunk2

@test thunk2() == 4

import KernelCompiler: KernelFunction, workgroupsize 
@testset "Intrinsics" begin
    function (kernel::KernelFunction{<:Any, :saxpy})(out)
        out[1] = workgroupsize()
        return nothing
    end

    kernel = KernelFunction{Tuple{Int, Int}, :saxpy}((5, 6))
    thunk = KernelCompiler.jit(kernel, Tuple{Vector{Tuple{Int, Int}}})

    out = Array{Tuple{Int, Int}}(undef, 64)
    thunk(out)
    @test out[1] == (5, 6)
end