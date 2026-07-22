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

