### Optimize
# Needs https://github.com/JuliaLang/julia/pull/38287
import Core.Compiler: optimize
function optimize(interp::KernelInterpreter, opt::OptimizationState, params::OptimizationParams, @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    ir = run_passes(opt.src, nargs, opt)
    Core.Compiler.finish(opt, params, ir, result)
end

import Core.Compiler: CodeInfo, convert_to_ircode, copy_exprargs, slot2reg, compact!, coverage_enabled, adce_pass!
import Core.Compiler: ssa_inlining_pass!, getfield_elim_pass!, type_lift_pass!, verify_ir, verify_linetable
function run_passes(ci::CodeInfo, nargs::Int, sv::OptimizationState)
    @info "Running passes"
    preserve_coverage = coverage_enabled(sv.mod)
    ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, sv)
    ir = slot2reg(ir, ci, nargs, sv)
    # TODO: Domsorting can produce an updated domtree - no need to recompute here
    ir = compact!(ir)
    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
    ir = compact!(ir)
    ir = getfield_elim_pass!(ir) # SROA
    ir = adce_pass!(ir)
    ir = type_lift_pass!(ir)
    ir = compact!(ir)
    verify_ir(ir)
    verify_linetable(ir.linetable)
    return ir
end