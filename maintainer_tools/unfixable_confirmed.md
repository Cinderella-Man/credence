# Confirmed-unfixable list

Stubs from `unfixable_unreviewed.md` that stage 2 (`stage_2_promote_non_fixable/`)
reviewed and **proved** have no safe, behaviour-preserving fix for any shape they
flag (or only a value-type-changing fix). Unlike `unfixable_unreviewed.md` — which
was auto-classified by the strict `unfixable_stub?` predicate and never reviewed —
every entry here is a distinct, freshly-proven correctness finding from an agent
that tried to author a fix and couldn't.

This is the durable queue for a later **manual** pass that distills each reason
into `CONTEXT.md` (policy) and `prompt.md` (so the rule-writing AI stops re-making
the same unsafe rewrites). The loop is sandboxed and never edits those shared docs.

Each entry records the rule path, its test file(s), the agent's reason, and the date.
## avoid_charlist_for_iteration — 2026-06-05
- Files:
  - `lib/pattern/avoid_charlist_for_iteration.ex`
  - `test/pattern/avoid_charlist_for_iteration_test.exs`
- Reason: to_charlist→graphemes is a value-type change (integer codepoints vs grapheme strings) on every input incl. ASCII; no safe subset.

## avoid_graphemes_for_byte_iteration — 2026-06-05
- Files:
  - `lib/pattern/avoid_graphemes_for_byte_iteration.ex`
  - `test/pattern/avoid_graphemes_for_byte_iteration_check_test.exs`
- Reason: fix swaps grapheme binaries for codepoint integers (value-type change); int-cmp predicate flips answer and <<char>> shape turns multibyte crash into a value

## no_body_destructure_of_param — 2026-06-05
- Files:
  - `lib/pattern/no_body_destructure_of_param.ex`
  - `test/pattern/no_body_destructure_of_param_test.exs`
- Reason: moving a refutable destructure to the head changes non-matching inputs from MatchError to FunctionClauseError, and with sibling clauses silently re-dispatches to a different clause/value; no irrefutable (always-matching) non-trivial pattern exists to narrow to.

## no_case_enum_at_nil — 2026-06-05
- Files:
  - `lib/pattern/no_case_enum_at_nil.ex`
  - `test/pattern/no_case_enum_at_nil_check_test.exs`
- Reason: Enum.fetch! diverges on every flagged input — ArgumentError→Enum.OutOfBoundsError on out-of-bounds, and raise→nil on nil-in-list (value-type change).

## no_combined_min_max_reduce — 2026-06-05
- Files:
  - `lib/pattern/no_combined_min_max_reduce.ex`
  - `test/pattern/no_combined_min_max_reduce_test.exs`
- Reason: reduce->Enum.min_max diverges on empty ({nil,nil} vs raise), tuple min/max order is undetermined by check, and collection reconstruction breaks on non-list enumerables; no safe subset.

## no_comprehension_then_flatten — 2026-06-05
- Files:
  - `lib/pattern/no_comprehension_then_flatten.ex`
  - `test/pattern/no_comprehension_then_flatten_test.exs`
- Reason: List.flatten is recursive (deep) while Enum.flat_map/concat are single-level and raise on scalar bodies; no static subset proving body is one-level/non-list is decidable.

## no_conditional_max_in_reduce — 2026-06-05
- Files:
  - `lib/pattern/no_conditional_max_in_reduce.ex`
  - `test/pattern/no_conditional_max_in_reduce_test.exs`
- Reason: reduce->filter+max is context-dependent, not behaviour-preserving (diverges on non-zero init, negative values, acc-referencing cond, side-effect order); no statically-identifiable safe subset to narrow to.

## no_enum_at_binary_search — 2026-06-05
- Files:
  - `lib/pattern/no_enum_at_binary_search.ex`
  - `test/pattern/no_enum_at_binary_search_test.exs`
- Reason: fix requires list⇒tuple value-type change across wrapper + recursive signature + all call sites; any local Enum.at→elem patch raises on oob/negative where Enum.at returns nil/from-end and isn't even O(1).

## no_enum_at_in_recursion — 2026-06-05
- Files:
  - `lib/pattern/no_enum_at_in_recursion.ex`
  - `test/pattern/no_enum_at_in_recursion_test.exs`
- Reason: only fixes are structural/multi-site (walk-by-pattern or hoist List.to_tuple to caller); local elem(List.to_tuple(l),i) differs on negative/out-of-range and stays O(n).

## no_enum_at_in_reduce — 2026-06-05
- Files:
  - `lib/pattern/no_enum_at_in_reduce.ex`
  - `test/pattern/no_enum_at_in_reduce_test.exs`
- Reason: Enum.at(list,i)→elem(List.to_tuple(list),i) over dynamic index differs on negative idx (last vs raise), out-of-bounds (nil vs raise), and non-list enumerables (List.to_tuple raises); no in-bounds-provable subset since literals are excluded.

## no_enum_chunk_every_for_adjacent_pairs — 2026-06-05
- Files:
  - `lib/pattern/no_enum_chunk_every_for_adjacent_pairs.ex`
  - `test/pattern/no_enum_chunk_every_for_adjacent_pairs_test.exs`
- Reason: fix needs semantic rewrite of arbitrary reduce callback; only structural alt (zip+tl) changes element type list->tuple and raises on non-list enumerables, unnarrowable from AST

## no_filter_then_flat_map — 2026-06-06
- Files:
  - `lib/pattern/no_filter_then_flat_map.ex`
  - `test/pattern/no_filter_then_flat_map_test.exs`
- Reason: filter|>flat_map fusion is single interleaved pass; reorders pred-vs-transform exceptions (e.g. [2,:sym]: ArithmeticError vs ArgumentError) — two-pass order has no fusing builtin, no safe core.

## no_filter_then_new — 2026-06-06
- Files:
  - `lib/pattern/no_filter_then_new.ex`
  - `test/pattern/no_filter_then_new_test.exs`
- Reason: only fix is interleaved `for`; reorders pred-vs-transform exceptions vs two-pass filter|>{MapSet,Map}.new (no two-pass collect builtin)

## no_group_by_identity — 2026-06-06
- Files:
  - `lib/pattern/no_group_by_identity.ex`
  - `test/pattern/no_group_by_identity_test.exs`
- Reason: only replacement (Enum.frequencies) returns %{v=>count} vs group_by's %{v=>[v,...]} — a value-type change, never equal for non-empty input

## no_integer_to_string_contains — 2026-06-06
- Files:
  - `lib/pattern/no_integer_to_string_contains.ex`
  - `test/pattern/no_integer_to_string_contains_test.exs`
- Reason: digit-membership rewrite flips the boolean on negative ints (digits go negative) and differs on non-int crash type (ArgumentError vs FunctionClauseError); sign/type of a variable arg can't be narrowed away.

