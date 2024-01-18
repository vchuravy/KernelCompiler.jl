using KernelCompiler
using Test

import KernelCompiler: Kernel, __context__ 

child(x) = x+1
const parent = Kernel((1,1), (x)->child(x))

@test parent(2) == 3
child(x) = x+2

@test parent(2) == 4

function (kernel::Kernel{<:Any, :context})()
    return __context__()
end
const context = Kernel{Tuple{Int, Int}, :context}((1, 1))
@test context() == (1,1)