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

## prefer_heredoc_for_multi_line_doc — 2026-06-16
- Files:
  - `lib/pattern/prefer_heredoc_for_multi_line_doc.ex`
  - `test/pattern/prefer_heredoc_for_multi_line_doc_fix_test.exs`
- Reason: delta swaps per-node patches for whole-file Sourceror.to_string render, which reformats unrelated code (e.g. `x+1`→`x + 1`, `z=y`→`z = y`) on any non-formatter-clean input — diverges from exact-same-answer bar.

## prefer_integer_digits_for_first_digit — 2026-06-16
- Files:
  - `lib/pattern/prefer_integer_digits_for_first_digit.ex`
  - `test/pattern/prefer_integer_digits_for_first_digit_check_test.exs`
  - `test/pattern/prefer_integer_digits_for_first_digit_equivalence_test.exs`
  - `test/pattern/prefer_integer_digits_for_first_digit_fix_test.exs`
- Reason: float input diverges (string path returns first digit, Integer.digits/1 raises) and base-type can't be proven integer statically — no safe core; fix also drops intermediate pipe ops (div(3)) by rebuilding from leftmost base.

## prefer_integer_to_binary_for_bit_length — 2026-06-16
- Files:
  - `lib/pattern/prefer_integer_to_binary_for_bit_length.ex`
  - `test/pattern/prefer_integer_to_binary_for_bit_length_check_test.exs`
  - `test/pattern/prefer_integer_to_binary_for_bit_length_equivalence_test.exs`
  - `test/pattern/prefer_integer_to_binary_for_bit_length_fix_test.exs`
- Reason: not behavior-preserving — float floor(:math.log(n)/:math.log(2))+1 diverges from integer_to_binary bit-length on 153+ large integers (e.g. n=2^48-1: 49 vs 48); added when n<0 clause changes function domain (crash→value); no statically-bounded safe core.

## prefer_integer_undigits — 2026-06-16
- Files:
  - `lib/pattern/prefer_integer_undigits.ex`
  - `test/pattern/prefer_integer_undigits_check_test.exs`
  - `test/pattern/prefer_integer_undigits_equivalence_test.exs`
  - `test/pattern/prefer_integer_undigits_fix_test.exs`
- Reason: not behavior-preserving — Integer.undigits/1 raises where the reduce returns a value: digit>=base (e.g. [12,5]: 125 vs ArgumentError), float elements (raise vs value), and any non-list enumerable (range/MapSet/stream — reduce accepts Enumerable, undigits requires a list). Check fires on syntactic reduce shape where enum is a variable, never statically provable to be an in-range integer list; only safe narrowing is a literal digit list (degenerate, matches no real code). Same no-safe-core outcome as prefer_integer_to_binary/prefer_integer_digits followups.

## prefer_map_intersect_over_mapset_intersection — 2026-06-16
- Files:
  - `lib/pattern/prefer_map_intersect_over_mapset_intersection.ex`
  - `test/pattern/prefer_map_intersect_over_mapset_intersection_check_test.exs`
  - `test/pattern/prefer_map_intersect_over_mapset_intersection_equivalence_test.exs`
  - `test/pattern/prefer_map_intersect_over_mapset_intersection_fix_test.exs`
- Reason: check flags bare pipeline the fix won't touch (check/fix disagree); wildcard merge_expr breaks on element-reference/side-effect ordering, common_keys binding deleted even if reused, and elem/2 crashes the fix on non-variable map args — no clean safe core without a full rewrite + intractable purity bound.

