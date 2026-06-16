# Followup — rules needing human attention

Stage 1 (`stage_1_promote_fixable_rules/review_loop.sh`) appends one section per
set it could not safely promote: no safe fix, duplicate, needs a shared-file
change, type change, or inconclusive. Each entry lists the set's files and the
one-line reason. Work these by hand later.
## no_if_boolean_result — 2026-06-16
- Files:
  - `lib/pattern/no_if_boolean_result.ex`
  - `test/pattern/no_if_boolean_result_check_test.exs`
  - `test/pattern/no_if_boolean_result_equivalence_test.exs`
  - `test/pattern/no_if_boolean_result_fix_test.exs`
- Reason: duplicate of live no_if_true_false (covers both or/and rewrites correctly); this rule's provably_boolean? unsoundly trusts ?-predicate calls and bare and/or conditions, both BadBooleanError divergences; safe core would be a strict subset of no_if_true_false, any fold is a shared-file change

## no_if_empty_for_enum_min_max — 2026-06-16
- Files:
  - `lib/pattern/no_if_empty_for_enum_min_max.ex`
  - `test/pattern/no_if_empty_for_enum_min_max_check_test.exs`
  - `test/pattern/no_if_empty_for_enum_min_max_equivalence_test.exs`
  - `test/pattern/no_if_empty_for_enum_min_max_fix_test.exs`
- Reason: delta extends matching to unrestricted Enum.filter/reject calls and collapses the original's two filter evaluations into one; diverges on impure/non-deterministic predicates (proven: original raises Enum.EmptyError where rewrite returns fallback) — contradicts no_double_filter's "never a call, rule out side-effecting double evaluation" convention; restore accepted bare-var version.

## no_list_foldl — 2026-06-16
- Files:
  - `lib/pattern/no_list_foldl.ex`
  - `test/pattern/no_list_foldl_check_test.exs`
  - `test/pattern/no_list_foldl_equivalence_test.exs`
  - `test/pattern/no_list_foldl_fix_test.exs`
- Reason: List.foldl(x,…)→Enum.reduce(x,…) broadens domain — original raises FunctionClauseError on non-list enumerables (map/range) where the rewrite succeeds; expression rewrite can't add an is_list guard (unlike no_manual_list_reduce), and the only provably-list case (literal lists) is too narrow to be useful.

## no_map_keys_or_values_for_iteration — 2026-06-16
- Files:
  - `lib/pattern/no_map_keys_or_values_for_iteration.ex`
  - `test/pattern/no_map_keys_or_values_for_iteration_check_test.exs`
  - `test/pattern/no_map_keys_or_values_for_iteration_equivalence_test.exs`
  - `test/pattern/no_map_keys_or_values_for_iteration_fix_test.exs`
- Reason: correct_capture_range's hand-rolled paren scanner miscounts char-literal ?) as a closing paren — regresses valid input `&(&1 == ?))` (was correct, now emits non-compiling `end))`); incomplete lexer trades one broken-capture class for another.

## no_redundant_local_capture — 2026-06-16
- Files:
  - `lib/pattern/no_redundant_local_capture.ex`
  - `test/pattern/no_redundant_local_capture_check_test.exs`
  - `test/pattern/no_redundant_local_capture_equivalence_test.exs`
  - `test/pattern/no_redundant_local_capture_fix_test.exs`
- Reason: scope-blind fix silently miscompiles — global var map rewrites every same-named var.(args) module-wide (a/n calls bar instead of foo) and whole-line removal drops neighboring statements' side effects; both pass the compile gate. Needs per-scope matching, a rewrite not a narrowing.

## no_unused_computation — 2026-06-16
- Files:
  - `lib/pattern/no_unused_computation.ex`
  - `test/pattern/no_unused_computation_check_test.exs`
  - `test/pattern/no_unused_computation_equivalence_test.exs`
  - `test/pattern/no_unused_computation_fix_test.exs`
- Reason: premise conflates purity with totality — every positive case (length/String.length/String.graphemes/abs/Enum.reverse, plus div/hd/String.to_integer) is partial and raises on some admitted input, so deleting the discarded call drops a crash; safe core (only is_*/total guards) is degenerate and excludes 100% of demonstrated cases.

## no_unused_underscore_assignment — 2026-06-16
- Files:
  - `lib/pattern/no_unused_underscore_assignment.ex`
  - `test/pattern/no_unused_underscore_assignment_check_test.exs`
  - `test/pattern/no_unused_underscore_assignment_equivalence_test.exs`
  - `test/pattern/no_unused_underscore_assignment_fix_test.exs`
- Reason: rule deletes the `_unused = <pure>` bindings the semantic UnusedVariable rule deliberately produces, breaking 4 end-to-end pipeline tests in shared test/credence_pipeline_test.exs (out of scope to change).

## prefer_bitshift_over_math_pow_for_power_of2 — 2026-06-16
- Files:
  - `lib/pattern/prefer_bitshift_over_math_pow_for_power_of2.ex`
  - `test/pattern/prefer_bitshift_over_math_pow_for_power_of2_check_test.exs`
  - `test/pattern/prefer_bitshift_over_math_pow_for_power_of2_equivalence_test.exs`
  - `test/pattern/prefer_bitshift_over_math_pow_for_power_of2_fix_test.exs`
- Reason: unsafe — trunc(2^x) ≠ 2^trunc(x) for non-integer x (2.5→5 vs 4) and pow overflows/raises for x≥1024 while shift returns a bignum; no non-degenerate safe core.

## prefer_chunk_over_indexed_reduce — 2026-06-16
- Files:
  - `lib/pattern/prefer_chunk_over_indexed_reduce.ex`
  - `test/pattern/prefer_chunk_over_indexed_reduce_check_test.exs`
  - `test/pattern/prefer_chunk_over_indexed_reduce_equivalence_test.exs`
  - `test/pattern/prefer_chunk_over_indexed_reduce_fix_test.exs`
- Reason: overfit template substitution — fix hardcodes a peak-count rewrite ignoring init acc / branch return values / boundary comparisons, and even the exact canonical snippet diverges under :strict (single-element [{}]/[%{}]/[[]] → orig 1, rewrite 0, since out-of-bounds Enum.at returns nil < tuple/map/list); no safe non-degenerate core.

