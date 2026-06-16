# Followup — rules needing human attention

Stage 1 (`stage_1_promote_fixable_rules/review_loop.sh`) appends one section per
set it could not safely promote: no safe fix, duplicate, needs a shared-file
change, type change, or inconclusive. Each entry lists the set's files and the
one-line reason. Work these by hand later.
## avoid_duplicate_enum_at — 2026-06-16
- Files:
  - `lib/pattern/avoid_duplicate_enum_at.ex`
  - `test/pattern/avoid_duplicate_enum_at_check_test.exs`
  - `test/pattern/avoid_duplicate_enum_at_equivalence_test.exs`
  - `test/pattern/avoid_duplicate_enum_at_fix_test.exs`
- Reason: fix introduces `<index>_elem` bindings that capture/clobber existing in-scope vars (e.g. pre-bound `mid_elem` used in a branch diverges); pattern rule can't see sibling/following code to guarantee a collision-free name, and it emits non-compiling code for inline `if` expressions

## avoid_length_guard_less_than2 — 2026-06-16
- Files:
  - `lib/pattern/avoid_length_guard_less_than2.ex`
  - `test/pattern/avoid_length_guard_less_than2_check_test.exs`
  - `test/pattern/avoid_length_guard_less_than2_equivalence_test.exs`
  - `test/pattern/avoid_length_guard_less_than2_fix_test.exs`
- Reason: duplicate of no_length_guard_to_pattern (same length-guard→pattern habit/target/helpers); fold <2/<=1 there — a shared-file change. Standalone rule also regresses compound `and` guards (drops the remaining condition) vs the sibling rule.

