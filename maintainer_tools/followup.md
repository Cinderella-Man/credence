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

