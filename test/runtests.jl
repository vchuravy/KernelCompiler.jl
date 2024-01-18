using KernelCompiler
using Test

# Can't run inside a testset :/
parent(x) = child(x)
child(x) = x+1

const thunk1 = KernelCompiler.Kernel(parent)

@test thunk1(2) == 3
child(x) = x+2

@test thunk1(2) == 4

parent() = child()
child() = 3

@test thunk1() == 3
child() = 4

@test thunk1() == 4

