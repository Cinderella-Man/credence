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

## no_list_as_optional_value — 2026-06-06
- Files:
  - `lib/pattern/no_list_as_optional_value.ex`
  - `test/pattern/no_list_as_optional_value_test.exs`
- Reason: []/[x]->nil/x sentinel collides with a nil payload ([nil] vs [] both become nil; payload is arbitrary input, not narrowable); fix also needs non-local caller seed rewrites the check can't do.

## no_list_replace_at_in_recursion — 2026-06-06
- Files:
  - `lib/pattern/no_list_replace_at_in_recursion.ex`
  - `test/pattern/no_list_replace_at_in_recursion_test.exs`
- Reason: only fix threads a tuple through the recursion (value-type change, non-local) and put_elem raises on the out-of-bounds/negative dynamic indices that List.replace_at/update_at silently tolerate

## no_list_replace_at_in_reduce — 2026-06-06
- Files:
  - `lib/pattern/no_list_replace_at_in_reduce.ex`
  - `test/pattern/no_list_replace_at_in_reduce_test.exs`
- Reason: only fix swaps the list accumulator for a map/tuple (Map.put/put_elem) — a value-type change spanning init+downstream, applies to all flagged shapes, no safe same-type core

## no_manual_bit_count — 2026-06-06
- Files:
  - `lib/pattern/no_manual_bit_count.ex`
  - `test/pattern/no_manual_bit_count_test.exs`
- Reason: non-local rewrite (delete 2 helper clauses + rewrite remote call sites) and check underspecifies popcount (admits non-popcount/list/tuple accumulators and negative/non-terminating inputs), so no behaviour-preserving patch exists for any flagged shape.

## no_manual_has_duplicates — 2026-06-06
- Files:
  - `lib/pattern/no_manual_has_duplicates.ex`
  - `test/pattern/no_manual_has_duplicates_test.exs`
- Reason: check flags the arity-2 accumulator helper, whose answer depends on the accumulator (do_check([1,2],%{1=>true})=true vs Enum.uniq!=list=false under :strict); the only equivalent rewrite (Enum.uniq(list)!=list) belongs to the un-flagged caller seeding %{} and still diverges on non-list/improper inputs, with no safe local subset.

## no_manual_sorted_merge — 2026-06-06
- Files:
  - `lib/pattern/no_manual_sorted_merge.ex`
  - `test/pattern/no_manual_sorted_merge_test.exs`
- Reason: Enum.sort(a++b) equals the manual merge only for already-sorted inputs (a runtime invariant); on unsorted inputs it differs (merge([3,1],[2])=[2,3,1] vs [1,2,3]), and no syntactic subset can guarantee sortedness.

## no_manual_top_k_reduce — 2026-06-06
- Files:
  - `lib/pattern/no_manual_top_k_reduce.ex`
  - `test/pattern/no_manual_top_k_reduce_test.exs`
- Reason: reduce returns a tuple but the only replacement (sort|>take) returns a list — value-type change; and check is purely structural (any </>/<=/>= + any 2-tuple body), never verifying aggregation, comparison direction, init ordering, or list-ness, so no same-answer fix exists for the admitted inputs.

## no_map_then_reduce — 2026-06-06
- Files:
  - `lib/pattern/no_map_then_reduce.ex`
  - `test/pattern/no_map_then_reduce_test.exs`
- Reason: fusing map-then-reduce reorders map/reduce side effects (mmmrrr→mrmrmr) and the 2-arity reduce form leaves the first source element unmapped ({4,3}); no safe core without an undecidable purity guarantee :strict forbids.

## no_min_max_reduce_with_index — 2026-06-06
- Files:
  - `lib/pattern/no_min_max_reduce_with_index.ex`
  - `test/pattern/no_min_max_reduce_with_index_test.exs`
- Reason: reduce's seed accumulator is an extra candidate that can be returned (proven {0,0} vs {3,1}); min_by/max_by has no seed, and check never constrains init to the enumerable's first element.

## no_reduce_for_partition — 2026-06-06
- Files:
  - `lib/pattern/no_reduce_for_partition.ex`
  - `test/pattern/no_reduce_for_partition_test.exs`
- Reason: check flags only the reduce node, whose value is reversed-order lists (or {list,int}); no Enum.split_with reproduces it, and matching the trailing reverses is unsafe (guard swallows errors a predicate raises)

## no_reduce_range_with_elem — 2026-06-06
- Files:
  - `lib/pattern/no_reduce_range_with_elem.ex`
  - `test/pattern/no_reduce_range_with_elem_test.exs`
- Reason: reduce-over-range+elem → zip/Tuple.to_list can't preserve answer; range bound never statically equals tuple_size (out-of-bounds elem raises while rewrite truncates), even the slimmest core diverges on the empty tuple (raises vs []), bodies/accumulators are arbitrary, and the order-fixing Enum.reverse is outside the flagged node.

## no_redundant_rem_guard — 2026-06-06
- Files:
  - `lib/pattern/no_redundant_rem_guard.ex`
  - `test/pattern/no_redundant_rem_guard_test.exs`
- Reason: only fix drops the parity guard, broadening the clause so negative-odd and non-integer inputs return a value instead of raising FunctionClauseError (raise→value, a kind change); proving those inputs are pre-empted needs non-local clause-coverage analysis no static rule can do.

## no_redundant_sort_comparator — 2026-06-06
- Files:
  - `lib/pattern/no_redundant_sort_comparator.ex`
  - `test/pattern/no_redundant_sort_comparator_check_test.exs`
- Reason: Enum.sort/1 differs from every flagged comparator on runtime-only facts static analysis can't exclude — strict `<` is unstable and reorders int/float value-equal-but-not-`===` elements ([1,2] vs [1.0,2]), crashes (FunctionClauseError) on wrong-arity/typed elements where sort/1 succeeds, and the `<=` variant short-circuits to a different ordering entirely.

## no_repeated_length_in_recursion — 2026-06-06
- Files:
  - `lib/pattern/no_repeated_length_in_recursion.ex`
  - `test/pattern/no_repeated_length_in_recursion_test.exs`
- Reason: fix requires adding a parameter (arity change) and rewriting every entry call site, which is an out-of-scope interface change and double-evaluates side-effecting call-site exprs; no arity-preserving rewrite removes the recompute, so no safe core.

## no_reverse_then_find — 2026-06-06
- Files:
  - `lib/pattern/no_reverse_then_find.ex`
  - `test/pattern/no_reverse_then_find_test.exs`
- Reason: removing the reverse forces a forward pass that evaluates pred on all elements, breaking reverse|>find's short-circuit-from-end; diverges (returns vs raises) on partial/side-effecting predicates, no static narrowing isolates a real safe core.

## no_reverse_uniq_reverse — 2026-06-06
- Files:
  - `lib/pattern/no_reverse_uniq_reverse.ex`
  - `test/pattern/no_reverse_uniq_reverse_test.exs`
- Reason: reverse|>uniq|>reverse keeps last occurrence (order-preserved); Enum.uniq keeps first, so the only replacement changes which elements survive — no same-answer fix.

