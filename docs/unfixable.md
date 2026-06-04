# Unfixable list

Rules auto-filtered out of the candidate queue by `scripts/move_unfixable_out.sh`
because they are **provably check-only** — they detect a problem but ship no real
fix, so by project policy (Credence has no warn-only mode) they cannot be accepted.

Detection is the strict, light static `unfixable_stub?` predicate (per kind):
- **pattern** — `fix_patches/2` is a single constant `[]` clause.
- **semantic** — every `fix/2` clause returns `source` verbatim.
- **syntax** — every `fix/1` clause returns `source` verbatim.

Anything subtler is left in the queue for the review loop's agent to judge.
Each entry below records the rule path, its test file(s), the reason, and the date.
## avoid_charlist_for_iteration (pattern) — 2026-06-04
- Rule: `lib/pattern/avoid_charlist_for_iteration.ex`
- Tests:
  - `test/pattern/avoid_charlist_for_iteration_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## avoid_graphemes_for_byte_iteration (pattern) — 2026-06-04
- Rule: `lib/pattern/avoid_graphemes_for_byte_iteration.ex`
- Tests:
  - `test/pattern/avoid_graphemes_for_byte_iteration_check_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_body_destructure_of_param (pattern) — 2026-06-04
- Rule: `lib/pattern/no_body_destructure_of_param.ex`
- Tests:
  - `test/pattern/no_body_destructure_of_param_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_case_enum_at_nil (pattern) — 2026-06-04
- Rule: `lib/pattern/no_case_enum_at_nil.ex`
- Tests:
  - `test/pattern/no_case_enum_at_nil_check_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_case_on_param_dispatch (pattern) — 2026-06-04
- Rule: `lib/pattern/no_case_on_param_dispatch.ex`
- Tests:
  - `test/pattern/no_case_on_param_dispatch_check_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_combined_min_max_reduce (pattern) — 2026-06-04
- Rule: `lib/pattern/no_combined_min_max_reduce.ex`
- Tests:
  - `test/pattern/no_combined_min_max_reduce_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_comprehension_then_flatten (pattern) — 2026-06-04
- Rule: `lib/pattern/no_comprehension_then_flatten.ex`
- Tests:
  - `test/pattern/no_comprehension_then_flatten_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_conditional_max_in_reduce (pattern) — 2026-06-04
- Rule: `lib/pattern/no_conditional_max_in_reduce.ex`
- Tests:
  - `test/pattern/no_conditional_max_in_reduce_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_double_filter (pattern) — 2026-06-04
- Rule: `lib/pattern/no_double_filter.ex`
- Tests:
  - `test/pattern/no_double_filter_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_enum_at_binary_search (pattern) — 2026-06-04
- Rule: `lib/pattern/no_enum_at_binary_search.ex`
- Tests:
  - `test/pattern/no_enum_at_binary_search_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_enum_at_in_recursion (pattern) — 2026-06-04
- Rule: `lib/pattern/no_enum_at_in_recursion.ex`
- Tests:
  - `test/pattern/no_enum_at_in_recursion_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_enum_at_in_reduce (pattern) — 2026-06-04
- Rule: `lib/pattern/no_enum_at_in_reduce.ex`
- Tests:
  - `test/pattern/no_enum_at_in_reduce_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_enum_chunk_every_for_adjacent_pairs (pattern) — 2026-06-04
- Rule: `lib/pattern/no_enum_chunk_every_for_adjacent_pairs.ex`
- Tests:
  - `test/pattern/no_enum_chunk_every_for_adjacent_pairs_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_fetch_then_update (pattern) — 2026-06-04
- Rule: `lib/pattern/no_fetch_then_update.ex`
- Tests:
  - `test/pattern/no_fetch_then_update_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_filter_then_flat_map (pattern) — 2026-06-04
- Rule: `lib/pattern/no_filter_then_flat_map.ex`
- Tests:
  - `test/pattern/no_filter_then_flat_map_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_filter_then_new (pattern) — 2026-06-04
- Rule: `lib/pattern/no_filter_then_new.ex`
- Tests:
  - `test/pattern/no_filter_then_new_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_group_by_identity (pattern) — 2026-06-04
- Rule: `lib/pattern/no_group_by_identity.ex`
- Tests:
  - `test/pattern/no_group_by_identity_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_hd_tl_when_cons_bound (pattern) — 2026-06-04
- Rule: `lib/pattern/no_hd_tl_when_cons_bound.ex`
- Tests:
  - `test/pattern/no_hd_tl_when_cons_bound_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_integer_to_string_contains (pattern) — 2026-06-04
- Rule: `lib/pattern/no_integer_to_string_contains.ex`
- Tests:
  - `test/pattern/no_integer_to_string_contains_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_list_as_optional_value (pattern) — 2026-06-04
- Rule: `lib/pattern/no_list_as_optional_value.ex`
- Tests:
  - `test/pattern/no_list_as_optional_value_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_list_concat_with_recursive_result (pattern) — 2026-06-04
- Rule: `lib/pattern/no_list_concat_with_recursive_result.ex`
- Tests:
  - `test/pattern/no_list_concat_with_recursive_result_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_list_delete_at_length (pattern) — 2026-06-04
- Rule: `lib/pattern/no_list_delete_at_length.ex`
- Tests:
  - `test/pattern/no_list_delete_at_length_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_list_delete_at_with_length (pattern) — 2026-06-04
- Rule: `lib/pattern/no_list_delete_at_with_length.ex`
- Tests:
  - `test/pattern/no_list_delete_at_with_length_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_list_pop_at_for_access (pattern) — 2026-06-04
- Rule: `lib/pattern/no_list_pop_at_for_access.ex`
- Tests:
  - `test/pattern/no_list_pop_at_for_access_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_list_replace_at_in_recursion (pattern) — 2026-06-04
- Rule: `lib/pattern/no_list_replace_at_in_recursion.ex`
- Tests:
  - `test/pattern/no_list_replace_at_in_recursion_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_list_replace_at_in_reduce (pattern) — 2026-06-04
- Rule: `lib/pattern/no_list_replace_at_in_reduce.ex`
- Tests:
  - `test/pattern/no_list_replace_at_in_reduce_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_manual_bit_count (pattern) — 2026-06-04
- Rule: `lib/pattern/no_manual_bit_count.ex`
- Tests:
  - `test/pattern/no_manual_bit_count_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_manual_count_with_predicate (pattern) — 2026-06-04
- Rule: `lib/pattern/no_manual_count_with_predicate.ex`
- Tests:
  - `test/pattern/no_manual_count_with_predicate_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_manual_find (pattern) — 2026-06-04
- Rule: `lib/pattern/no_manual_find.ex`
- Tests:
  - `test/pattern/no_manual_find_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_manual_has_duplicates (pattern) — 2026-06-04
- Rule: `lib/pattern/no_manual_has_duplicates.ex`
- Tests:
  - `test/pattern/no_manual_has_duplicates_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_manual_list_reduce (pattern) — 2026-06-04
- Rule: `lib/pattern/no_manual_list_reduce.ex`
- Tests:
  - `test/pattern/no_manual_list_reduce_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_manual_list_reverse (pattern) — 2026-06-04
- Rule: `lib/pattern/no_manual_list_reverse.ex`
- Tests:
  - `test/pattern/no_manual_list_reverse_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_manual_sorted_merge (pattern) — 2026-06-04
- Rule: `lib/pattern/no_manual_sorted_merge.ex`
- Tests:
  - `test/pattern/no_manual_sorted_merge_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_manual_top_k_reduce (pattern) — 2026-06-04
- Rule: `lib/pattern/no_manual_top_k_reduce.ex`
- Tests:
  - `test/pattern/no_manual_top_k_reduce_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_map_then_reduce (pattern) — 2026-06-04
- Rule: `lib/pattern/no_map_then_reduce.ex`
- Tests:
  - `test/pattern/no_map_then_reduce_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_min_max_reduce_with_index (pattern) — 2026-06-04
- Rule: `lib/pattern/no_min_max_reduce_with_index.ex`
- Tests:
  - `test/pattern/no_min_max_reduce_with_index_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_nested_then (pattern) — 2026-06-04
- Rule: `lib/pattern/no_nested_then.ex`
- Tests:
  - `test/pattern/no_nested_then_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_reduce_for_partition (pattern) — 2026-06-04
- Rule: `lib/pattern/no_reduce_for_partition.ex`
- Tests:
  - `test/pattern/no_reduce_for_partition_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_reduce_range_with_elem (pattern) — 2026-06-04
- Rule: `lib/pattern/no_reduce_range_with_elem.ex`
- Tests:
  - `test/pattern/no_reduce_range_with_elem_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_redundant_comparison_guard (pattern) — 2026-06-04
- Rule: `lib/pattern/no_redundant_comparison_guard.ex`
- Tests:
  - `test/pattern/no_redundant_comparison_guard_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_redundant_rem_guard (pattern) — 2026-06-04
- Rule: `lib/pattern/no_redundant_rem_guard.ex`
- Tests:
  - `test/pattern/no_redundant_rem_guard_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_redundant_sort_comparator (pattern) — 2026-06-04
- Rule: `lib/pattern/no_redundant_sort_comparator.ex`
- Tests:
  - `test/pattern/no_redundant_sort_comparator_check_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_repeated_div_rem (pattern) — 2026-06-04
- Rule: `lib/pattern/no_repeated_div_rem.ex`
- Tests:
  - `test/pattern/no_repeated_div_rem_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_repeated_length_in_recursion (pattern) — 2026-06-04
- Rule: `lib/pattern/no_repeated_length_in_recursion.ex`
- Tests:
  - `test/pattern/no_repeated_length_in_recursion_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_reverse_then_find (pattern) — 2026-06-04
- Rule: `lib/pattern/no_reverse_then_find.ex`
- Tests:
  - `test/pattern/no_reverse_then_find_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_reverse_uniq_reverse (pattern) — 2026-06-04
- Rule: `lib/pattern/no_reverse_uniq_reverse.ex`
- Tests:
  - `test/pattern/no_reverse_uniq_reverse_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_starts_with_own_prefix (pattern) — 2026-06-04
- Rule: `lib/pattern/no_starts_with_own_prefix.ex`
- Tests:
  - `test/pattern/no_starts_with_own_prefix_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_trivial_delegation (pattern) — 2026-06-04
- Rule: `lib/pattern/no_trivial_delegation.ex`
- Tests:
  - `test/pattern/no_trivial_delegation_check_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## no_uniq_then_count (pattern) — 2026-06-04
- Rule: `lib/pattern/no_uniq_then_count.ex`
- Tests:
  - `test/pattern/no_uniq_then_count_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## prefer_enum_split (pattern) — 2026-06-04
- Rule: `lib/pattern/prefer_enum_split.ex`
- Tests:
  - `test/pattern/prefer_enum_split_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

## prefer_regex_match (pattern) — 2026-06-04
- Rule: `lib/pattern/prefer_regex_match.ex`
- Tests:
  - `test/pattern/prefer_regex_match_check_test.exs`
- Reason: check-only stub — every fix clause is the verbatim dead form (`unfixable_stub?`).

