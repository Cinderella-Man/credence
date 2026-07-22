# Followup — rules needing human attention

Stage 1 (`stage_1_promote_fixable_rules/review_loop.sh`) appends one section per
set it could not safely promote: no safe fix, duplicate, needs a shared-file
change, type change, or inconclusive. Each entry lists the set's files and the
one-line reason. Work these by hand later.

_No open items._

<!--
Resolved 2026-06-17 — test/pattern/assumptions_filtering_test.exs: NOT an orphan.
It is an end-to-end integration test for the assumptions/switch-filter subsystem
(`:strict`/`:default`/per-switch promises) through the public API — the loop's
per-rule orphan detector false-positived because there is no same-named rule
file. Passes (9 tests) and carries unique coverage (config-precedence changing
real `fix` output; the "filtered rule named in an explicit rules: list warns but
stays filtered" path). Kept. Optional tidy: move to test/ level (alongside
assumptions_test.exs / credence_test.exs) and rename the module off `.Pattern`
so a future scan won't re-flag it.
-->
## fix_string_replace_multi_arity_fn — 2026-07-22
- Files:
  - `lib/pattern/fix_string_replace_multi_arity_fn.ex`
  - `test/pattern/fix_string_replace_multi_arity_fn_check_test.exs`
  - `test/pattern/fix_string_replace_multi_arity_fn_equivalence_test.exs`
  - `test/pattern/fix_string_replace_multi_arity_fn_fix_test.exs`
- Reason: false premise — String.replace/3 is /4 with default [], so removing [] leaves the flagged arity-2 crash fully intact (verified: both raise identical FunctionClauseError); fix does not repair what check flags and the message/moduledoc assert wrong Elixir semantics

## prefer_head_pattern_over_tail_destructure — 2026-07-22
- Files:
  - `lib/pattern/prefer_head_pattern_over_tail_destructure.ex`
  - `test/pattern/prefer_head_pattern_over_tail_destructure_check_test.exs`
  - `test/pattern/prefer_head_pattern_over_tail_destructure_equivalence_test.exs`
  - `test/pattern/prefer_head_pattern_over_tail_destructure_fix_test.exs`
- Reason: every firing case changes MatchError to FunctionClauseError on a 1-element/improper list (accepted rules treat a different exception as a different answer; no assumptions declared), so the safe core is empty without a guard-rewrite redesign; also unfixed collision bugs: inner-head name reused (e.g. [a|b] with [a|_]=b yields unifying [a, a | _rest]), repeated _rest unifies across two fixed params, and rescue blocks referencing the tail var are not checked.

## prefer_stdlib_gcd — 2026-07-22
- Files:
  - `lib/pattern/prefer_stdlib_gcd.ex`
  - `test/pattern/prefer_stdlib_gcd_check_test.exs`
  - `test/pattern/prefer_stdlib_gcd_equivalence_test.exs`
  - `test/pattern/prefer_stdlib_gcd_fix_test.exs`
- Reason: every firing case diverges under :strict — hand-rolled gcd returns sign-carrying results (gcd(-4,0)=-4 vs Integer.gcd=4; verified for all negative pairs) and raises ArithmeticError vs FunctionClauseError on non-integers, with no assumptions declared and no applicable switch (negative ints are a plain-value gap, not rare text), so the safe core is empty without a caller-guard-analysis redesign; the fix is also unsound on its own terms: it deletes the defp pair but only rewrites calls whose args are both bare vars, leaving calls like gcd(a * b, b) (or &gcd/2 captures, or extra gcd clauses outside the consecutive pair) dangling against a now-undefined function.

## fix_apply_on_function_reference — 2026-07-22
- Files:
  - `lib/semantic/fix_apply_on_function_reference.ex`
  - `test/semantic/fix_apply_on_function_reference_check_test.exs`
  - `test/semantic/fix_apply_on_function_reference_fix_test.exs`
- Reason: matches a fabricated diagnostic — Code.with_diagnostics emits nothing for apply(fun_ref, :call, []) (compiles clean; runtime-only ArgumentError whose message also lacks "apply(:call, [])"), so match? can never fire on real input and the rule is unreachable dead code; the fix is also broken independently (rebuilds receiver with [] args so apply(s.get_clock(x), :call, []) drops x; MatchError on single-element dot receivers like apply(f.(), :call, []); whole-file rewrite ignoring the diagnostic line; misrewrites module-valued fields where apply(cfg.mod, :call, []) validly calls cfg.mod.call/0)

## fix_bitwise_infix_operator — 2026-07-22
- Files:
  - `lib/semantic/fix_bitwise_infix_operator.ex`
  - `test/semantic/fix_bitwise_infix_operator_check_test.exs`
  - `test/semantic/fix_bitwise_infix_operator_fix_test.exs`
- Reason: matches a fabricated diagnostic — bare bitwise infix operators (|||, &&&, <<<, >>>, ~~~, ^^^) all parse fine without import Bitwise (verified on Elixir 1.20: they emit "undefined function |||/2"-style errors, never "syntax error"), so match? can only fire on unrelated syntax errors whose quoted snippet happens to contain the token (the test's own @real_diag is really a <-> error); the rule is also internally contradictory — any genuine syntax-error diagnostic means Sourceror.parse_string fails, so fix is a guaranteed no-op on every input match? admits (flag-without-fix), and the claimed companion FixErlangBitwiseBif does not exist; retargeting to the real undefined-function diagnostic would be a redesign, not a narrowing

## fix_cond_branch_assignment_in_guard — 2026-07-23
- Files:
  - `lib/semantic/fix_cond_branch_assignment_in_guard.ex`
  - `test/semantic/fix_cond_branch_assignment_in_guard_check_test.exs`
  - `test/semantic/fix_cond_branch_assignment_in_guard_fix_test.exs`
- Reason: unreachable in production — match? requires reading diag.file, but the pipeline compiles in-memory (file: "credence_check.ex", nonexistent, File.read fails → match? always false; tests pass only via fabricated tmp-file diagnostics); and even a message-only match? is shadowed by FixCaseBranchAssignmentScope, which claims every `undefined variable "…"` diagnostic and sorts first at equal priority 500 in the single-rule-per-diagnostic dispatch — making it reachable needs folding into that accepted rule or a phase change, both outside this set; fix also silently deletes cond branches other than the assign/guard/true trio

## fix_cond_branch_assignment_scope — 2026-07-23
- Files:
  - `lib/semantic/fix_cond_branch_assignment_scope.ex`
  - `test/semantic/fix_cond_branch_assignment_scope_check_test.exs`
  - `test/semantic/fix_cond_branch_assignment_scope_fix_test.exs`
- Reason: unreachable in production — match? needs File.read(diag.file) but the pipeline compiles in-memory (file "credence_check.ex" never exists, so match? is always false; tests fabricate tmp-file diagnostics), and a message-only match? is shadowed by accepted FixCaseBranchAssignmentScope, which claims every `undefined variable` diagnostic and sorts first at equal priority 500 in single-rule dispatch; winning priority would instead shadow/regress that accepted rule since identical messages make the shapes indistinguishable at match? time — reachability requires folding into FixCase or a phase change, both outside this set

