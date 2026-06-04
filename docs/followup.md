# Follow-up list

Items pulled out of the candidate queue that need dedicated human attention
(not handled by the per-rule review loop). Reviewed case by case.

## Global / end-to-end test suites — 2026-06-03
- Files:
  - `test/credence_test.exs`
  - `test/debug_ast_test.exs`
  - `test/fix_examples_test.exs`
  - `test/fix_showcase_test.exs`
- Reason: these are whole-system suites, not tied to a single rule. Their
  `evolution` versions assert the behaviour of rules that have not been accepted
  yet, so they can't be reviewed in isolation.
- Suggested action: review **last**, once the rule set has settled, and reconcile
  each assertion against the rules that actually landed.

## `lib/syntax.ex` — runner behaviour change — **REJECTED** (rules were misfiled) — 2026-06-03
- File: `lib/syntax.ex`
- Decision: **do not bring the `evolution` runner change over. Keep `lib/syntax.ex`
  as-is** (accepted branch). The `apply_rules_traced/2` extraction is a clean DRY
  refactor, but the behaviour change it enables — run syntax rules even when the
  source already parses — is a workaround for two rules that were filed in the wrong
  phase, and it ships real defects.
- Why the change is wrong, not just incomplete:
  1. **Masking regression (confirmed empirically).** The top-level `Credence.analyze/2`
     gate is `if Enum.any?(syntax_issues) -> %{valid: false, issues: syntax_issues}`
     (stops; never runs semantic/pattern). It assumes "syntax issue ⇒ won't parse."
     Once syntax rules fire on parseable code, a single misplaced `@moduledoc`
     suppresses **every** semantic + pattern issue in the file. Demonstrated: identical
     code with `length(x) == 0` reported only `:module_attr_outside_module` with the
     attr misplaced, but `:no_length_comparison_for_empty` once placed correctly.
     `evolution` did **not** change `lib/credence.ex`, so this regression is live.
  2. Stale docs (moduledoc + `fix_with_trace/2` @doc now contradict behaviour) and no
     parse-verify on the now-active `{:ok}` branch (valid code can be turned invalid
     silently, with no downstream revert).
- Root cause: the two rules that *needed* this change target **parseable** code, so by
  the phase taxonomy (syntax = won't parse; semantic = compiler diagnostic; pattern =
  AST-detectable) they are **not syntax rules**. Both `@moduledoc`-before-`defmodule`
  and a literal-list typespec parse fine and raise on compile with **0 captured
  diagnostics** (so semantic, which is diagnostic-driven, can't host them either) — but
  they are cleanly **AST-detectable**, i.e. **pattern** rules.
- Action: **reclassify** `fix_module_attr_outside_module` and `fix_typespec_literal_list`
  from syntax → **pattern** (rewrite detection from string-scanning to AST-walking;
  pattern's `apply_or_revert` compiles the *result*, so a non-compiling input with a
  compilable fix is fine). Then `lib/syntax.ex` needs **no change**, the masking bug
  never arises, and the 4 genuinely-unparseable fixers stay as syntax rules.
- **DONE (2026-06-03):** both reclassified + reimplemented as AST-based pattern rules,
  each narrowed to its safe core and shipped with split check/fix tests:
  - `lib/pattern/no_literal_list_typespec.ex` — `[t, t]`→`{t, t}` in `@spec` returns;
    narrowed to all-type-call elements (skips keyword lists, `[t, ...]`, `[:ok, :error]`,
    single-element lists).
  - `lib/pattern/no_attr_before_defmodule.ex` — moves `@moduledoc/@doc/@spec/@type` that
    precede a `defmodule` into it; **dropped** the destructive de-dup and the
    `defmodule Solution` wrap (intent-guessing); existing-module-only.
  `lib/syntax.ex` left byte-identical; the evolution runner change remains rejected.
  Full suite green (3213 tests). The old syntax entries are removed from `pr_diff.md`.
## avoid_graphemes_enum_count_with_predicate — 2026-06-04
- Files:
  - `lib/pattern/avoid_graphemes_enum_count_with_predicate.ex`
  - `test/pattern/avoid_graphemes_enum_count_with_predicate_check_test.exs`
  - `test/pattern/avoid_graphemes_enum_count_with_predicate_fix_test.exs`
- Reason: delta drops single-codepoint narrowing + promise; fix now changes answer (e.g. "" 0→14, "ab" 0→2)

## no_case_digit_to_integer — 2026-06-04
- Files:
  - `lib/pattern/no_case_digit_to_integer.ex`
  - `test/pattern/no_case_digit_to_integer_test.exs`
- Reason: case is partial (raises off "0".."9"); String.to_integer is total — differs on "10","-1","+5","00","07" etc. No safe core to narrow to.

## no_cond_two_clauses — 2026-06-04
- Files:
  - `lib/pattern/no_cond_two_clauses.ex`
  - `test/pattern/no_cond_two_clauses_check_test.exs`
  - `test/pattern/no_cond_two_clauses_fix_test.exs`
- Reason: complement extension is not behavior-preserving — original cond evaluates the guard operands twice in the else path (first guard, then complement) while the if/else rewrite evaluates them once; diverges on side-effecting/non-idempotent operands (e.g. `IO.puts(x)==:e`/`!=`, `next_id()<=max`/`>max`). The accepted `true`-second-guard case never had this since `true` is not evaluated; the rule can't statically restrict to pure operands.

## no_dead_map_update — 2026-06-04
- Files:
  - `lib/pattern/no_dead_map_update.ex`
  - `test/pattern/no_dead_map_update_test.exs`
- Reason: not behavior-preserving — Map.update/4 runs fun on the existing value when the key is present, so removing the dead update drops side effects and exceptions; original `%{prev: "x"} |> Map.update(:prev, 0, &(&1 - 1)) |> Map.drop([:prev])` raises ArithmeticError while `Map.drop(map, [:prev])` returns %{}. No statically-provable safe core (can't prove key absent or fun total/pure).

## no_destructure_reconstruct — 2026-06-04
- Files:
  - `lib/pattern/no_destructure_reconstruct.ex`
  - `test/pattern/no_destructure_reconstruct_test.exs`
- Reason: new tuple/binary families lack the multi-arg guard the cons family has — `def f({...} = tuple, {...} = tuple)` forces arg1==arg2 (silent behavior change), and `<<len, data::binary-size(len)>>` underscores `len` to `_` leaving `size(len)` undefined (non-compiling fix); delta is not behavior-preserving.

## no_doc_false_on_private — 2026-06-04
- Files:
  - `lib/pattern/no_doc_false_on_private.ex`
  - `test/pattern/no_doc_false_on_private_test.exs`
- Reason: delta broadens match from literal `@doc false` to any `@doc <expr>`; fix deletes `@doc` whose argument has compile-time side effects (e.g. `@doc (IO.puts(...) && "d")`, interpolation), dropping the evaluation — not behavior-preserving.

## no_enum_at_negative_index — 2026-06-04
- Files:
  - `lib/pattern/no_enum_at_negative_index.ex`
  - `test/pattern/no_enum_at_negative_index_fix_test.exs`
- Reason: delta's plan_inline_for_statement rework emits the pattern match before the Enum.reverse binding (e.g. `result = Enum.at(sorted, -2) + 1` → `[_, sorted_neg2 | _] = sorted_reversed` precedes `sorted_reversed = Enum.reverse(sorted)`), producing non-compiling/behavior-changing output; the delta also replaced exact `==` heredoc fix-tests with `=~` substring checks that hide this ordering regression.

## no_enum_into_empty_map — 2026-06-04
- Files:
  - `lib/pattern/no_enum_into_empty_map.ex`
  - `test/pattern/no_enum_into_empty_map_test.exs`
- Reason: rule flags Enum.into(enum, %{}) which the curated shared suite test/credence_test.exs:777 explicitly asserts must stay clean ("collect into any collectable"); reconciling requires editing that out-of-scope shared file, so the full suite cannot go green.

## no_enum_slice_with_length — 2026-06-04
- Files:
  - `lib/pattern/no_enum_slice_with_length.ex`
  - `test/pattern/no_enum_slice_with_length_test.exs`
- Reason: not behavior-preserving — Enum.slice/3 raises FunctionClauseError when length(var)-k is negative (any list shorter than k, e.g. the empty list since k>0), while the range fix Enum.slice(var, 0..-(k+1)//1) returns []; no narrowing fixes this since the list length is unknowable statically.

## no_explicit_max_reduce — 2026-06-04
- Files:
  - `lib/pattern/no_explicit_max_reduce.ex`
  - `test/pattern/no_explicit_max_reduce_test.exs`
- Reason: delta's :max if-classification never checks branch direction, so a min reducer `if x > acc, do: acc, else: x` is flagged :max and the new `Enum.max([acc | enum])` fix path rewrites it into a max (behavior-changing on valid input).

## no_explicit_min_reduce — 2026-06-04
- Files:
  - `lib/pattern/no_explicit_min_reduce.ex`
  - `test/pattern/no_explicit_min_reduce_test.exs`
- Reason: delta broadens the __block__ clause from `[body]` (single-expr only) to `[_|_]` recurse-on-last, so multi-statement reduce bodies like `y = x*2; min(y, acc)` are now flagged and rewritten to `Enum.min(enum)` — dropping the transformation and init (behavior-changing); the accepted version did not flag these.

## no_explicit_sum_reduce — 2026-06-04
- Files:
  - `lib/pattern/no_explicit_sum_reduce.ex`
  - `test/pattern/no_explicit_sum_reduce_test.exs`
- Reason: new &+/2 clause leaves init (_acc) a wildcard, so Enum.reduce(enum, <non-zero>, &+/2) is now flagged and rewritten to Enum.sum(enum), dropping the accumulator (behavior-changing; e.g. reduce([1,2,3],10,&+/2)==16 vs Enum.sum==6); accepted version did not flag capture syntax.

## no_filter_then_map — 2026-06-04
- Files:
  - `lib/pattern/no_filter_then_map.ex`
  - `test/pattern/no_filter_then_map_test.exs`
- Reason: filter|>map is two-pass (all preds, then all transforms); `for` interleaves, so on admitted inputs like [2,:sym] (pred rem(x,2)==0, transform hd(x)) it raises a different exception (ArithmeticError vs ArgumentError); destructuring patterns also turn a FunctionClauseError into a silent skip — no safe narrowable core under :strict.

## no_grapheme_palindrome_check — 2026-06-04
- Files:
  - `lib/pattern/no_grapheme_palindrome_check.ex`
  - `test/pattern/no_grapheme_palindrome_check_test.exs`
- Reason: delta re-adds String.to_charlist form (codepoint reverse) and rewrites it to String.reverse (grapheme reverse) — diverges on multi-codepoint graphemes, behavior-changing; accepted version deliberately excluded this

## no_guard_equality_for_pattern_match — 2026-06-04
- Files:
  - `lib/pattern/no_guard_equality_for_pattern_match.ex`
  - `test/pattern/no_guard_equality_for_pattern_match_test.exs`
- Reason: failed accept gate (pattern needs no_guard_equality_for_pattern_match_check_test.exs + no_guard_equality_for_pattern_match_fix_test.exs)

## no_identity_function_in_enum — 2026-06-04
- Files:
  - `lib/pattern/no_identity_function_in_enum.ex`
  - `test/pattern/no_identity_function_in_enum_test.exs`
- Reason: failed accept gate (pattern needs no_identity_function_in_enum_check_test.exs + no_identity_function_in_enum_fix_test.exs)

## no_if_subtraction_for_max — 2026-06-04
- Files:
  - `lib/pattern/no_if_subtraction_for_max.ex`
  - `test/pattern/no_if_subtraction_for_max_check_test.exs`
  - `test/pattern/no_if_subtraction_for_max_fix_test.exs`
- Reason: max(0, x - y) evaluates the subtraction unconditionally — on non-number operands the original `if x > y, do: x - y, else: 0` returns 0 (cond false) while the rewrite raises ArithmeticError; `>=` also turns float-zero 0.0 into integer 0. Not narrowable syntactically (operands are runtime-bound; can't prove numbers), and the type change can't be promised away.

## no_integer_to_string_digits — 2026-06-04
- Files:
  - `lib/pattern/no_integer_to_string_digits.ex`
  - `test/pattern/no_integer_to_string_digits_test.exs`
- Reason: unsound on every input — Integer.digits yields raw digit values [1,0,1] while String.to_charlist(Integer.to_string(...)) yields ASCII codepoints [49,48,49] and String.graphemes yields a list of strings ["1","0","1"]; no base/number matches, and graphemes also changes type, so there is no safe narrow core.

## no_integer_to_string_length — 2026-06-04
- Files:
  - `lib/pattern/no_integer_to_string_length.ex`
  - `test/pattern/no_integer_to_string_length_test.exs`
- Reason: unsound on negative integers — String.length(Integer.to_string(n, base)) counts the leading "-" (e.g. -123 base 10 → 4) while length(Integer.digits(n, base)) does not (→ 3), so they differ by 1 on every negative input; n is runtime-bound, so non-negativity can't be proven syntactically and the only "safe" narrow core is non-negative integer literals (degenerate/useless).

## no_list_append_in_reduce — 2026-06-04
- Files:
  - `lib/pattern/no_list_append_in_reduce.ex`
  - `test/pattern/no_list_append_in_reduce_test.exs`
- Reason: delta widens check to flag unfixable cases (non-empty initial, ++ nested in case/if, ++ not the return expr) while fix stays gated on empty-initial + last-expression ++; breaks check/fix-agreement bar and Credence has no warn-only mode

## no_list_to_tuple_for_access — 2026-06-04
- Files:
  - `lib/pattern/no_list_to_tuple_for_access.ex`
  - `test/pattern/no_list_to_tuple_for_access_test.exs`
- Reason: failed accept gate (pattern needs no_list_to_tuple_for_access_check_test.exs + no_list_to_tuple_for_access_fix_test.exs)

## no_manual_enum_uniq — 2026-06-04
- Files:
  - `lib/pattern/no_manual_enum_uniq.ex`
  - `test/pattern/no_manual_enum_uniq_test.exs`
- Reason: new :__block__ collapse fix leaves an unbound var / drops the return value when the destructured tuple var is used elsewhere in the block (e.g. {result,_}=reduce; IO.inspect(result); Enum.reverse(result) -> Enum.uniq(list); IO.inspect(result)) — breaks exact-same-answer.

## no_manual_frequencies — 2026-06-04
- Files:
  - `lib/pattern/no_manual_frequencies.ex`
  - `test/pattern/no_manual_frequencies_test.exs`
- Reason: new frequencies_by feature breaks exact-same-answer — flags derived keys referencing `acc` (fix leaves `acc` unbound, won't compile) and ignores the Map.update increment fn (weighted `&(&1 + 2)` becomes plain count).

## no_manual_integer_undigits — 2026-06-04
- Files:
  - `lib/pattern/no_manual_integer_undigits.ex`
  - `test/pattern/no_manual_integer_undigits_test.exs`
- Reason: no safe same-answer fix — reduce form diverges for ranges/float elements (undigits raises); join form is not equivalent to Integer.undigits (string concat+parse vs positional base-10) and diverges/raises on multi-digit/empty inputs; no meaningful statically-safe core

## no_manual_list_delete_at — 2026-06-04
- Files:
  - `lib/pattern/no_manual_list_delete_at.ex`
  - `test/pattern/no_manual_list_delete_at_test.exs`
- Reason: not behavior-preserving — list & index are always variables; negative index diverges (take(x,-1)++drop(x,0) != delete_at(x,-1)) and non-list enumerables (Range/Map) make List.delete_at raise while manual form works; no statically-safe core in this matching shape.

## no_manual_list_replace_at — 2026-06-04
- Files:
  - `lib/pattern/no_manual_list_replace_at.ex`
  - `test/pattern/no_manual_list_replace_at_test.exs`
- Reason: not behavior-preserving — list & index always bare variables, no statically-safe core; manual form raises MatchError on out-of-range/non-list while List.replace_at returns list unchanged (OOB) or raises FunctionClauseError (Range/Map), and negative-OOB replaces index 0 vs unchanged — same shape as no_manual_list_delete_at.

