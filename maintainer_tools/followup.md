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

## no_manual_map_key_union — 2026-06-04
- Files:
  - `lib/pattern/no_manual_map_key_union.ex`
  - `test/pattern/no_manual_map_key_union_test.exs`
- Reason: not behavior-preserving — manual concat-uniq preserves m1-then-m2 first-occurrence order while Map.keys(Map.merge) returns plain map term order (e.g. %{b,d}/%{a,c} → [:b,:d,:c,:a] vs [:c,:b,:a,:d]); result is an order-observable list and map args are always variables, so no statically-safe core.

## no_manual_string_reverse — 2026-06-04
- Files:
  - `lib/pattern/no_manual_string_reverse.ex`
  - `test/pattern/no_manual_string_reverse_test.exs`
- Reason: delta folds String.codepoints into this no-promise :strict rule, but codepoints-reverse-join != String.reverse for multi-codepoint graphemes (proven "́e" vs "é"); unsafe fix and duplicates NoCodepointStringReverse which already gates codepoints behind single_codepoint_graphemes.

## no_map_keys_enum_lookup — 2026-06-04
- Files:
  - `lib/pattern/no_map_keys_enum_lookup.ex`
  - `test/pattern/no_map_keys_enum_lookup_test.exs`
- Reason: sort_by delta not behavior-preserving — stable sort over an order-observable key list; for maps >32 entries Map.keys order is reversed vs direct Enum order, so tied sort keys diverge (proven), and map arg is always a bare variable so no safe static core.

## no_map_then_aggregate — 2026-06-04
- Files:
  - `lib/pattern/no_map_then_aggregate.ex`
  - `test/pattern/no_map_then_aggregate_test.exs`
- Reason: constructor_step? allows args [0,1], so `enum |> Enum.map(f) |> MapSet.new(g)` (valid MapSet.new/2 with transform) is flagged and auto-fixed to `MapSet.new(enum, f)`, silently dropping g — proven different result (set of f(x) vs g(f(x))); same for Map.new. Also max_by/min_by are flagged check-only with a non-equivalent "use directly" suggestion (mapped-element vs original-element return), violating check/fix agreement.

## no_map_then_flatten — 2026-06-04
- Files:
  - `lib/pattern/no_map_then_flatten.ex`
  - `test/pattern/no_map_then_flatten_test.exs`
- Reason: map|>List.flatten -> Enum.flat_map not behavior-preserving (List.flatten is deep+raise-tolerant, flat_map is shallow+raises on non-list); no safe static core to narrow to

## no_multiple_enum_at — 2026-06-04
- Files:
  - `lib/pattern/no_multiple_enum_at.ex`
  - `test/pattern/no_multiple_enum_at_test.exs`
- Reason: delta adds fix for Enum.at/3 default forms (direct 3-arg + piped 2-arg) — rewrite to `[a,b,c | _] = Enum.reverse(var)` drops the default and raises MatchError on out-of-bounds instead of returning the default (proven: Enum.at([1,2],-3,0)=0 vs MatchError); not behavior-preserving.

## no_range_comparison_for_membership — 2026-06-04
- Files:
  - `lib/pattern/no_range_comparison_for_membership.ex`
  - `test/pattern/no_range_comparison_for_membership_test.exs`
- Reason: fix not behavior-preserving — float x (e.g. 5.5 or 10.0) satisfies `x>=a and x<=b` (true) but `x in a..b` is false (range membership requires integer); no static way to prove x is integer, so no safe core

## no_redundant_length_with_regex — 2026-06-05
- Files:
  - `lib/pattern/no_redundant_length_with_regex.ex`
  - `test/pattern/no_redundant_length_with_regex_test.exs`
- Reason: unsound premise — regex `$` permits a trailing newline, so `String.length(x)==N` is NOT redundant with `^...{N}$`; fix changes the answer on any N-char string + "\n" (e.g. "1234567890\n": before=false, after=true). No safe core keeps the `$`-anchored shape; dot `.` element also multibyte-unsafe.

## no_redundant_negated_guard — 2026-06-05
- Files:
  - `lib/pattern/no_redundant_negated_guard.ex`
  - `test/pattern/no_redundant_negated_guard_test.exs`
- Reason: delta's underscore-prefixing changes behavior — `f(x, _x, y) when x != y` becomes `f(_x, _x, _y)`, an accidental non-linear pattern forcing arg1==arg2; f(1,99,2) returns :neq before, crashes after.

## no_rem_for_parity_check — 2026-06-05
- Files:
  - `lib/pattern/no_rem_for_parity_check.ex`
  - `test/pattern/no_rem_for_parity_check_test.exs`
- Reason: unsafe on every input — rem(x,2) raises ArithmeticError on non-integers while Integer.is_even/is_odd (guarded by is_integer) returns false, and the ==1/!=1 cases are wrong for negative integers (rem(-3,2)==1 is false but is_odd(-3) is true); no safe core remains.

## no_reverse_then_sort — 2026-06-05
- Files:
  - `lib/pattern/no_reverse_then_sort.ex`
  - `test/pattern/no_reverse_then_sort_check_test.exs`
  - `test/pattern/no_reverse_then_sort_fix_test.exs`
- Reason: unsound premise — Enum.sort is a stable sort, so reverse-then-sort differs from sort whenever the list has distinct-but-equal-under-comparator elements (e.g. Enum.sort([1,1.0])=[1,1.0] vs Enum.sort(Enum.reverse([1,1.0]))=[1.0,1], === false); no syntactic narrowing can guarantee absence of such elements, so no safe core.

## no_single_use_binding — 2026-06-05
- Files:
  - `lib/pattern/no_single_use_binding.ex`
  - `test/pattern/no_single_use_binding_check_test.exs`
  - `test/pattern/no_single_use_binding_fix_test.exs`
- Reason: unsafe — check counts var uses only in the next statement, so it removes a binding still referenced later (e.g. `v=foo(x); v>0; bar(v)` → `foo(x)>0; bar(v)`, unbound-var CompileError); also conflicts head-on with accepted no_kernel_op_in_pipeline, breaking end-to-end showcase tests outside the set.

## no_sort_with_key_comparator — 2026-06-05
- Files:
  - `lib/pattern/no_sort_with_key_comparator.ex`
  - `test/pattern/no_sort_with_key_comparator_test.exs`
- Reason: unsafe at every variant — strict </> comparators aren't stable like sort_by's <=/>= (reverse equal-key runs, e.g. [{:a,2},{:b,1},{:c,2},{:d,1},{:e,2}] differs), and for <=/>= the tuple pattern {_,_,w1} raises FunctionClauseError on wrong-arity tuples while &elem(&1,2) silently succeeds; no syntactic narrowing guarantees uniform tuple arity, so no safe core.

## no_split_then_insert — 2026-06-05
- Files:
  - `lib/pattern/no_split_then_insert.ex`
  - `test/pattern/no_split_then_insert_test.exs`
- Reason: unsafe — List.insert_at differs from split-then-concat on negative index (appends at end vs inserts before last) and raises FunctionClauseError on non-list enumerables that Enum.split accepts; only safe core (literal list + literal non-neg int index) never occurs in real code, so no useful narrowing.

## no_string_split_whitespace_regex — 2026-06-05
- Files:
  - `lib/pattern/no_string_split_whitespace_regex.ex`
  - `test/pattern/no_string_split_whitespace_regex_test.exs`
- Reason: unsafe at every variant — String.split/1 trims and uses Unicode-whitespace semantics that no ~r/\s/ regex matches; 2-arg ~r/\s+/ differs on padded/Unicode input, 3-arg ~r/\s/[u] differs on em-space (no u) or non-breaking space (with u); arg is a runtime value so no syntactic safe core.

## no_sum_by_reduce — 2026-06-05
- Files:
  - `lib/pattern/no_sum_by_reduce.ex`
  - `test/pattern/no_sum_by_reduce_test.exs`
- Reason: conflicts with accepted end-to-end showcase tests (fix_showcase_test.exs:109, credence_test.exs:1080) that expect `acc + String.length(el)` reduce left unrewritten — fix needs out-of-set changes; also misfires on acc-referencing transforms (e.g. `acc + acc * x`) emitting unbound-`acc` code that won't compile.

## no_with_as_boolean_chain — 2026-06-05
- Files:
  - `lib/pattern/no_with_as_boolean_chain.ex`
  - `test/pattern/no_with_as_boolean_chain_check_test.exs`
  - `test/pattern/no_with_as_boolean_chain_fix_test.exs`
- Reason: unsafe — `with true <-` chain always yields a strict boolean and never crashes, but the `and`-chain returns the last predicate's truthy value (true and 5 == 5) and raises BadBooleanError on a non-boolean earlier predicate (nil/5); safe only when every RHS is syntactically boolean (comparison/guard), which excludes all predicate-function chains the rule targets.

## fix_range_step — 2026-06-05
- Files:
  - `lib/semantic/fix_range_step.ex`
  - `test/semantic/fix_range_step_fix_test.exs`
- Reason: rule never fires on real diagnostics — the range-step warning reports position: 0 (real line only in the undeclared `stacktrace` field), so extract_line→0→idx -1→no-op; a working fix needs shared-framework position normalization (out of scope) and the text substitution is also unsafe (replaces all/substring occurrences).

## unused_variable — 2026-06-05
- Files:
  - `lib/semantic/unused_variable.ex`
  - `test/semantic/unused_variable_test.exs`
- Reason: failed accept gate (semantic needs ≥1 unused_variable*_check_test + ≥1 unused_variable*_fix_test)

## test/pattern/debug_ast_test.exs — 2026-06-05
- Reason: orphan test — no owning rule in tree or sister.

## no_manual_list_reverse — 2026-06-06
- Files:
  - `lib/pattern/no_manual_list_reverse.ex`
  - `test/pattern/no_manual_list_reverse_test.exs`
- Reason: duplicates already-promoted no_manual_list_reduce (manual reverse is a fold with update [h|acc]; its own fix test "cons-building update" already flags+fixes this exact shape) — fold/drop

## no_nested_then — 2026-06-06
- Files:
  - `lib/pattern/no_nested_then.ex`
  - `test/pattern/no_nested_then_test.exs`
- Reason: flattening then-closures leaks param bindings (proven: shadowing {20,1}vs{20,2}; binding() [:z]vs[:a,:r1,:z]); a safe fix needs scope-aware restructuring (fresh-name hoisting + binding/var! exclusion + statement-position detection), no clean slim core authorable in a single-rule review — inconclusive

