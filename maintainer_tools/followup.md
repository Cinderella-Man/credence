# Followup — rules needing human attention

Stage 1 (`stage_1_promote_fixable_rules/review_loop.sh`) appends one section per
set it could not safely promote: no safe fix, duplicate, needs a shared-file
change, type change, or inconclusive. Each entry lists the set's files and the
one-line reason. Work these by hand later.
## prefer_function_capture — 2026-06-16
- Files:
  - `lib/pattern/prefer_function_capture.ex`
  - `test/pattern/prefer_function_capture_check_test.exs`
  - `test/pattern/prefer_function_capture_equivalence_test.exs`
  - `test/pattern/prefer_function_capture_fix_test.exs`
- Reason: safe after narrowing to identifier-named calls (orig over-fired {x}->&{}/1, <<x>>->&<<>>/1, operators) but firing on showcase modules breaks 3 shared golden suites (fix_examples/fix_showcase/credence_test) that need regeneration outside the set

## prefer_function_clauses_for_list_patterns — 2026-06-16
- Files:
  - `lib/pattern/prefer_function_clauses_for_list_patterns.ex`
  - `test/pattern/prefer_function_clauses_for_list_patterns_check_test.exs`
  - `test/pattern/prefer_function_clauses_for_list_patterns_equivalence_test.exs`
  - `test/pattern/prefer_function_clauses_for_list_patterns_fix_test.exs`
- Reason: unsafe — fires on non-total list cases (CaseClauseError→FunctionClauseError) and its "already-covered" dropping ignores guards/clause-order, silently dropping a live case branch (f([],5): :a→:after); safe narrow guts flagship fixtures and overlaps accepted no_case_on_param_dispatch.

