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

## prefer_enum_join — 2026-06-17
- Files:
  - `lib/semantic/prefer_enum_join.ex`
  - `test/semantic/prefer_enum_join_check_test.exs`
  - `test/semantic/prefer_enum_join_fix_test.exs`
- Reason: duplicate of UndefinedFunction (already matches "String.join/2 is undefined or private"); fold as a one-line @qualified_replacements entry {"String","join",2} => {:rename,"Enum","join"} instead of a parallel module whose match? over-broadly matches *String.join and which relies on alphabetical priority-500 tie-break to avoid shadowing

## prefer_enum_slice_over_list_slice — 2026-06-17
- Files:
  - `lib/semantic/prefer_enum_slice_over_list_slice.ex`
  - `test/semantic/prefer_enum_slice_over_list_slice_check_test.exs`
  - `test/semantic/prefer_enum_slice_over_list_slice_fix_test.exs`
- Reason: duplicate of UndefinedFunction (already matches "List.slice/3 is undefined or private" via qualified-ref regex, severity :warning); fold as one-line @qualified_replacements entry {"List","slice",3} => {:rename,"Enum","slice"} instead of a parallel module — shared-file edit, out of scope.

## prefer_map_size_kernel — 2026-06-17
- Files:
  - `lib/semantic/prefer_map_size_kernel.ex`
  - `test/semantic/prefer_map_size_kernel_check_test.exs`
  - `test/semantic/prefer_map_size_kernel_fix_test.exs`
- Reason: duplicate — UndefinedFunction.match? already fires on "Map.size/1 is deprecated"; fold into its @qualified_replacements (needs a new bare-Kernel-rename variant in undefined_function.ex, a shared-file change) rather than ship a parallel module

## prefer_tl_over_enum_tail — 2026-06-17
- Files:
  - `lib/semantic/prefer_tl_over_enum_tail.ex`
  - `test/semantic/prefer_tl_over_enum_tail_check_test.exs`
  - `test/semantic/prefer_tl_over_enum_tail_fix_test.exs`
- Reason: duplicate — UndefinedFunction.match? already fires on "Enum.tail/1 is undefined or private" (parse_qualified_ref returns {"Enum","tail",1}); fold as a bare-Kernel rename of Enum.tail→tl into its @qualified_replacements (needs a new bare-Kernel-rename variant in undefined_function.ex, a shared-file change) rather than ship a parallel module.

## close_unclosed_fn_delimiter — 2026-06-17
- Files:
  - `lib/syntax/close_unclosed_fn_delimiter.ex`
  - `test/syntax/close_unclosed_fn_delimiter_analyze_test.exs`
  - `test/syntax/close_unclosed_fn_delimiter_fix_test.exs`
- Reason: misfires on valid standalone-fn code (f = fn x -> foo(if .. end) end); real-bug vs valid differs only by paren depth, untrackable by regex on non-parsing source (parens in strings/charlists); also insert_ends drops a paren on multi-paren case. No safe regex-narrowable core.

## no_end_keyword_variable — 2026-06-17
- Files:
  - `lib/syntax/no_end_keyword_variable.ex`
  - `test/syntax/no_end_keyword_variable_analyze_test.exs`
  - `test/syntax/no_end_keyword_variable_fix_test.exs`
- Reason: line-regex cannot tell a variable-return/use `end` from a block-closing `end` (or heredoc/string text) on unparseable source — fix renames real block closers at colliding indent and string contents; syntax phase has no parse-revert; no safe narrow core.

## no_for_comprehension_by_step — 2026-06-17
- Files:
  - `lib/syntax/no_for_comprehension_by_step.ex`
  - `test/syntax/no_for_comprehension_by_step_analyze_test.exs`
  - `test/syntax/no_for_comprehension_by_step_fix_test.exs`
- Reason: line-regex misfires on unparseable files — flags & corrupts valid `for ... do ... end` lines whose body string contains " by " (e.g. `for x <- 1..10 do IO.puts("written by hand") end` → broken output); syntax phase has no parse-revert; fix hardcodes `<=` (wrong for negative step); target syntax is speculative; no safe narrow core distinguishes bare `by` from `by`-in-string.

## no_markdown_code_fences — 2026-06-17
- Files:
  - `lib/syntax/no_markdown_code_fences.ex`
  - `test/syntax/no_markdown_code_fences_analyze_test.exs`
  - `test/syntax/no_markdown_code_fences_fix_test.exs`
- Reason: line-regex strips fence lines anywhere in an unparseable file, corrupting markdown fences inside docstrings/heredocs (proven: @moduledoc content mutated); syntax phase has no parse-revert; no safe narrow core distinguishes a wrapping fence from a fence inside a string. Same class as no_for_comprehension_by_step / no_end_keyword_variable.

## no_output_marker_lines — 2026-06-17
- Files:
  - `lib/syntax/no_output_marker_lines.ex`
  - `test/syntax/no_output_marker_lines_analyze_test.exs`
  - `test/syntax/no_output_marker_lines_fix_test.exs`
- Reason: line-regex strips `---WORD---` lines anywhere in an unparseable file, including inside heredocs/docstrings (proven: @moduledoc content corrupted); syntax phase has no per-rule parse-revert; no safe narrow core distinguishes a wrapping marker from a marker that is string content. Same class as no_markdown_code_fences / no_for_comprehension_by_step / no_end_keyword_variable.

## no_reserved_word_variable — 2026-06-17
- Files:
  - `lib/syntax/no_reserved_word_variable.ex`
  - `test/syntax/no_reserved_word_variable_analyze_test.exs`
  - `test/syntax/no_reserved_word_variable_fix_test.exs`
- Reason: line-regex on unparseable source corrupts reserved words inside string literals & @moduledoc heredocs (proven: {before, after} in a docstring → after_val while real error untouched); syntax phase has no per-rule parse-revert; analyze/fix regexes diverge (fix's is mangled by Elixir string-escaping); duplicates already-rejected no_end_keyword_variable for `end`; no safe narrow core distinguishes a binding from a block-closing keyword or string content. Same class as no_end_keyword_variable / no_markdown_code_fences.

## no_spec_do_block — 2026-06-17
- Files:
  - `lib/syntax/no_spec_do_block.ex`
  - `test/syntax/no_spec_do_block_analyze_test.exs`
  - `test/syntax/no_spec_do_block_fix_test.exs`
- Reason: line-regex rewrites `@spec do` lines anywhere in an unparseable file, corrupting `@spec do ... end` inside docstrings/heredocs (proven: @moduledoc content mangled); syntax phase has no per-rule parse-revert; no safe narrow core distinguishes a real syntax error from string content; target syntax also speculative. Same class as no_markdown_code_fences / no_end_keyword_variable.

## no_while_keyword — 2026-06-17
- Files:
  - `lib/syntax/no_while_keyword.ex`
  - `test/syntax/no_while_keyword_analyze_test.exs`
  - `test/syntax/no_while_keyword_fix_test.exs`
- Reason: line-regex flags `while <cond> do` lines anywhere in valid source — proven to misfire inside an @moduledoc heredoc (line 5 flagged, code parses), and the fix would mangle that docstring; same rejected class as no_markdown_code_fences / no_spec_do_block (syntax phase has no per-rule parse-revert, no safe narrow core distinguishing a real loop from string content). Also `while c do ... end` is parseable Elixir (call to undefined `while`), not a true syntax error, and the while→tail-recursion rewrite is a speculative heuristic (guesses accumulator/loop/free vars), not behavior-preserving on general input.

## prefer_cond_do_keyword — 2026-06-17
- Files:
  - `lib/syntax/prefer_cond_do_keyword.ex`
  - `test/syntax/prefer_cond_do_keyword_analyze_test.exs`
  - `test/syntax/prefer_cond_do_keyword_fix_test.exs`
- Reason: line-regex rewrites `cond ->` anywhere in an unparseable file, corrupting `cond ->` text inside @moduledoc/heredocs (proven: docstring mangled while real error is elsewhere `def f([`); analyze flags the same valid doc line; syntax phase has no per-rule parse-revert and fix/analyze get no parse-error location, so no safe narrow core distinguishes a real syntax error from string content; narrowing needs error meta passed into the rule (shared Rule behaviour + phase change), out of scope. Same class as no_while_keyword / no_spec_do_block / no_markdown_code_fences.

## prefer_fn_end_syntax — 2026-06-17
- Files:
  - `lib/syntax/prefer_fn_end_syntax.ex`
  - `test/syntax/prefer_fn_end_syntax_analyze_test.exs`
  - `test/syntax/prefer_fn_end_syntax_fix_test.exs`
- Reason: line-regex on unparseable source corrupts `->` inside @moduledoc heredocs (proven: docstring `acc -> acc * 2` rewritten while real error `def f([` untouched) and wraps valid multi-clause `fn` 2-arg clauses; even the happy path is broken (`f = x -> foo(x)` -> `f = fn x -> foo(x end)`, won't parse). Same rejected class as no_while_keyword/no_spec_do_block; no parse-error location into rule, no safe narrow core.

## prefer_list_update_at — 2026-06-17
- Files:
  - `lib/syntax/prefer_list_update_at.ex`
  - `test/syntax/prefer_list_update_at_analyze_test.exs`
  - `test/syntax/prefer_list_update_at_fix_test.exs`
- Reason: List.update_elem(...) is valid Elixir that parses, so the syntax phase (runs only on unparseable source) never reaches this rule on its own target — proven dead; and when a real syntax error elsewhere makes a file unparseable, its naive string match rewrites the text inside @moduledoc docstrings/string literals (proven corruption) — same rejected class as no_while_keyword/prefer_cond_do_keyword. Belongs in a pattern/semantic AST phase (out-of-scope shared-file change); no safe narrow core in syntax.

