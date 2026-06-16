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

## prefer_map_size — 2026-06-16
- Files:
  - `lib/pattern/prefer_map_size.ex`
  - `test/pattern/prefer_map_size_check_test.exs`
  - `test/pattern/prefer_map_size_equivalence_test.exs`
  - `test/pattern/prefer_map_size_fix_test.exs`
- Reason: duplicate — both shapes (Map.keys|>Enum.count and Enum.count(Map.keys)) already flagged by live no_enum_count_for_length (Map.keys is in its @list_returning); prefer_map_size's scope is a strict subset. Fold the Map.keys(var) case into that rule to emit map_size/1, which requires editing a file outside this set.

## prefer_negate_if_true_false — 2026-06-16
- Files:
  - `lib/pattern/prefer_negate_if_true_false.ex`
  - `test/pattern/prefer_negate_if_true_false_check_test.exs`
  - `test/pattern/prefer_negate_if_true_false_equivalence_test.exs`
  - `test/pattern/prefer_negate_if_true_false_fix_test.exs`
- Reason: overlaps live no_if_true_false (double-fires in analyze on `if cond do false else <bool-expr/true> end`; no_if_true_false collapses those first/better). Safe + has a unique non-boolean-else core, but de-duping needs folding no_if_true_false's territory check — a shared-file decision, out of scope.

## prefer_pattern_matching_for_empty_string — 2026-06-17
- Files:
  - `lib/pattern/prefer_pattern_matching_for_empty_string.ex`
  - `test/pattern/prefer_pattern_matching_for_empty_string_check_test.exs`
  - `test/pattern/prefer_pattern_matching_for_empty_string_equivalence_test.exs`
  - `test/pattern/prefer_pattern_matching_for_empty_string_fix_test.exs`
  - `test/pattern/prefer_pattern_matching_for_empty_string_property_test.exs`
- Reason: unsafe — String.trim(var)=="" rewritten to ""-pattern-match diverges on whitespace strings (e.g. " "), which single_codepoint_graphemes admits; trim's whitespace semantics are orthogonal to the codepoint promise, no safe narrow core, property test masks it via an unenforced no-whitespace guard.

## prefer_prepend_in_accumulator — 2026-06-17
- Files:
  - `lib/pattern/prefer_prepend_in_accumulator.ex`
  - `test/pattern/prefer_prepend_in_accumulator_check_test.exs`
  - `test/pattern/prefer_prepend_in_accumulator_equivalence_test.exs`
  - `test/pattern/prefer_prepend_in_accumulator_fix_test.exs`
- Reason: unsafe — List.last(acc) reads the tail but the fix substitutes head (front) and swaps append→prepend; equivalent only for single-element accumulator seeds. Public build_groups/2 admits multi-element seeds ([5,1]→before [[2,1,5]] vs after [[5,1],[2]]); equivalence test masks it with single-element seeds only. No safe core (can't prove acc is single-element at entry).

## prefer_remove_unused_private_fn_param — 2026-06-17
- Files:
  - `lib/pattern/prefer_remove_unused_private_fn_param.ex`
  - `test/pattern/prefer_remove_unused_private_fn_param_check_test.exs`
  - `test/pattern/prefer_remove_unused_private_fn_param_equivalence_test.exs`
  - `test/pattern/prefer_remove_unused_private_fn_param_fix_test.exs`
- Reason: unsafe — removing a defp param deletes the call-site arg expr (drops side effects/raises, e.g. compute(x, IO.puts("hi"))→compute(x)); call/head rewrite is arity-blind (foo/2+foo/3 → duplicate foo(a) clauses + undefined vars, won't compile), strands &name/2 captures, and groups defp globally across modules. No safe narrow core.

## prefer_reverse_for_palindrome_check — 2026-06-17
- Files:
  - `lib/pattern/prefer_reverse_for_palindrome_check.ex`
  - `test/pattern/prefer_reverse_for_palindrome_check_check_test.exs`
  - `test/pattern/prefer_reverse_for_palindrome_check_equivalence_test.exs`
  - `test/pattern/prefer_reverse_for_palindrome_check_fix_test.exs`
- Reason: semantics-blind match — fires on lookalikes that aren't palindrome checks (if-condition, base-case body, else branch, and Enum.at assignments are all unchecked wildcards) and forcibly rewrites to list == Enum.reverse(list); proven divergence (flipped !=/false-base lookalike returns true on [1,2,3,1] vs fix's false). Even a fully-locked core diverges on non-list inputs (length raises ArgumentError vs fix returns false on maps). No safe narrow core; also overfit to hardcoded names palindrome_check/palindrome_helper?.

## prefer_string_at_for_char_access — 2026-06-17
- Files:
  - `lib/pattern/prefer_string_at_for_char_access.ex`
  - `test/pattern/prefer_string_at_for_char_access_check_test.exs`
  - `test/pattern/prefer_string_at_for_char_access_equivalence_test.exs`
  - `test/pattern/prefer_string_at_for_char_access_fix_test.exs`
- Reason: semantics-blind — fires on any x = List.to_string([y]) (y opaque var); fix <<y::utf8>> raises ArgumentError on binary/charlist y (valid List.to_string inputs return a string), and y's integer-codepoint-ness is unprovable from the AST, so no safe narrow core. Also rebinds body_var globally ignoring shadowing.

## prefer_string_capitalize — 2026-06-17
- Files:
  - `lib/pattern/prefer_string_capitalize.ex`
  - `test/pattern/prefer_string_capitalize_check_test.exs`
  - `test/pattern/prefer_string_capitalize_equivalence_test.exs`
  - `test/pattern/prefer_string_capitalize_fix_test.exs`
- Reason: manual first-char String.upcase pattern is not equivalent to String.capitalize/1 — diverges on Unicode special-casing (ß→SS vs Ss, ligature ﬁ→FI vs Fi, digraph ǆ→Ǆ vs ǅ); divergence is input-dependent and unprovable from the AST, so no safe narrow core. Also the fix hardcodes "capitalize_string(string)" while the check fires on any function name, renaming other-named defps and breaking their callers.

## prefer_string_first_last — 2026-06-17
- Files:
  - `lib/pattern/prefer_string_first_last.ex`
  - `test/pattern/prefer_string_first_last_check_test.exs`
  - `test/pattern/prefer_string_first_last_equivalence_test.exs`
  - `test/pattern/prefer_string_first_last_fix_test.exs`
- Reason: semantics-blind + diverges on empty string — String.split_at("",1)→{"",""} so orig "" == nil (false) vs fix nil == nil (true); emptiness unprovable from AST. Also the case subject is unchecked (_subject ignored in check & fix), so it fires on any `case f(x) do {first,_rest} -> last = String.last(x); first == last end` lookalike and rewrites to String.first(x)==String.last(x). No safe narrow core.

## prefer_tuple_for_random_access — 2026-06-17
- Files:
  - `lib/pattern/prefer_tuple_for_random_access.ex`
  - `test/pattern/prefer_tuple_for_random_access_check_test.exs`
  - `test/pattern/prefer_tuple_for_random_access_equivalence_test.exs`
  - `test/pattern/prefer_tuple_for_random_access_fix_test.exs`
- Reason: Enum.fetch!→List.to_tuple+elem diverges on negative index (returns vs raises), non-list enumerables (List.to_tuple raises on range/map/stream), and exception type; var-type/index-sign unprovable from AST, no safe core.

## avoid_binary_mid_pattern — 2026-06-17
- Files:
  - `lib/semantic/avoid_binary_mid_pattern.ex`
  - `test/semantic/avoid_binary_mid_pattern_check_test.exs`
  - `test/semantic/avoid_binary_mid_pattern_fix_test.exs`
- Reason: fix changes last byte from integer to 1-byte binary (binary_part/3), inverting `first == last` true→false; also leaves middle var unbound if used, and relaxes the >=2-byte match — type change, no safe core.

## avoid_remote_function_in_guard — 2026-06-17
- Files:
  - `lib/semantic/avoid_remote_function_in_guard.ex`
  - `test/semantic/avoid_remote_function_in_guard_check_test.exs`
  - `test/semantic/avoid_remote_function_in_guard_fix_test.exs`
- Reason: fix ignores diagnostic position and rewrites every module-wide def pair whose guard holds a Module.fun call — valid guard-safe guards (e.g. Bitwise.band) get merged into an `if` that propagates errors the guard swallowed (divergence on valid code); also matches name+arity only, not head patterns, so the merged clause drops fallback bindings (unbound vars). Safe core needs diagnostic-line targeting + identical heads = fix rewrite, not a check narrow.

