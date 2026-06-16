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

