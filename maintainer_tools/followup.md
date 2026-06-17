# Followup — rules needing human attention

Stage 1 (`stage_1_promote_fixable_rules/review_loop.sh`) appends one section per
set it could not safely promote: no safe fix, duplicate, needs a shared-file
change, type change, or inconclusive. Each entry lists the set's files and the
one-line reason. Work these by hand later.

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

## prefer_recursion_over_while — 2026-06-17
- Files:
  - `lib/syntax/prefer_recursion_over_while.ex`
  - `test/syntax/prefer_recursion_over_while_analyze_test.exs`
  - `test/syntax/prefer_recursion_over_while_fix_test.exs`
- Reason: duplicate of already-rejected no_while_keyword; `while c do..end` parses (syntax phase never reaches it on its own target), line-regex corrupts `while..do` inside @moduledoc heredocs of unparseable files, and the while→tail-recursion fix is a speculative non-behavior-preserving heuristic. No safe narrow core in syntax phase.

## prefer_scan_over_scanl — 2026-06-17
- Files:
  - `lib/syntax/prefer_scan_over_scanl.ex`
  - `test/syntax/prefer_scan_over_scanl_analyze_test.exs`
  - `test/syntax/prefer_scan_over_scanl_fix_test.exs`
- Reason: proven dead in syntax phase — Enum.scanl(...) is valid syntax (undefined-fn call parses), so the phase (runs only on unparseable source) never invokes this rule on its own target; as a passenger on otherwise-unparseable files its global String.replace corrupts "Enum.scanl(" inside heredocs/strings. Semantic mistake; belongs in pattern/semantic phase (shared-file change, out of scope). Same class as rejected prefer_list_update_at/no_while_keyword.

## prefer_single_doc_attribute — 2026-06-17
- Files:
  - `lib/syntax/prefer_single_doc_attribute.ex`
  - `test/syntax/prefer_single_doc_attribute_analyze_test.exs`
  - `test/syntax/prefer_single_doc_attribute_fix_test.exs`
- Reason: global fix corrupts valid closed @doc heredocs (content beginning with "@doc" → whole block deleted) when riding as passenger on otherwise-unparseable files; "closing-triple-quotes" target parses so phase never reaches it (proven dead); no safe narrow core without parse-error location passed into rule (shared behaviour+phase change, out of scope). Same class as no_while_keyword/prefer_cond_do_keyword.

## test/pattern/assumptions_filtering_test.exs — 2026-06-17
- Reason: orphan test — no owning rule in tree or sister.

