# Plan — Big-bang migration to patch-based rule interface

## Context

The Pattern pipeline today has every fixable rule do its own
`Sourceror.parse_string!` → `Macro.postwalk` → `Sourceror.to_string`
round-trip, with the orchestrator also re-parsing per iteration. Three
recently-migrated rules (`no_list_to_tuple_for_access`,
`no_length_comparison_for_empty`, `no_map_then_aggregate`) instead emit
byte-range patches via `Sourceror.patch_string/2` — preserving layout
better and exposing a more uniform shape.

Driver for this change: **architectural cleanliness**, not perf. One
universal rule interface, no boilerplate, no per-rule round-trip,
layout-safe by construction. Perf wins are incidental.

## Design (locked in via grilling)

### Universal rule interface

```elixir
# lib/pattern/rule.ex
@callback check(ast :: Macro.t(), opts :: keyword()) :: [Credence.Issue.t()]
@callback fix(ast :: Macro.t(), opts :: keyword()) :: [patch]
@callback fixable?() :: boolean()
@callback priority() :: integer()

@type patch :: %{
  range: %{start: Keyword.t(), end: Keyword.t()},
  change: String.t()
}
```

- `check/2` returns issues (unchanged shape).
- `fix/2` returns a list of patches. Empty list = no change.
- Both callbacks receive **Sourceror AST** (not `Code.string_to_quoted`
  AST). One parser, one shape, everywhere.
- Rules that need raw source bytes (e.g. `no_trailing_newline_in_doc`)
  read it via `opts[:source]` — convention preserved.

### Orchestrator (`lib/pattern.ex`)

Sequential application with re-parse between rules — same mental
model as today, just expressed via patches.

```elixir
defp run_fixable_rules(fixable, source, opts) do
  ast = Sourceror.parse_string!(source)

  Enum.reduce(fixable, {source, ast, []}, fn rule, {src, ast, applied} ->
    name = RuleHelpers.rule_name(rule)
    check_opts = Keyword.put(opts, :source, src)

    case rule.check(ast, check_opts) do
      [] -> {src, ast, applied}
      issues ->
        case rule.fix(ast, check_opts) do
          [] ->
            Logger.debug("[credence_fix] #{name}: no patches emitted")
            {src, ast, applied}

          patches ->
            new_src = Sourceror.patch_string(src, patches)
            apply_or_revert(rule, name, src, ast, new_src, issues, applied)
        end
    end
  end)
end

defp apply_or_revert(rule, name, src, ast, new_src, issues, applied) do
  cond do
    new_src == src ->
      {src, ast, applied}

    not RuleHelpers.compiles?(new_src) ->
      Logger.warning("[credence_fix] #{name}: produced non-compiling output, reverting")
      {src, ast, [{rule, :reverted} | applied]}

    true ->
      new_ast = Sourceror.parse_string!(new_src)
      RuleHelpers.log_diff(name, src, new_src)
      {new_src, new_ast, [{rule, length(issues)} | applied]}
  end
end
```

- Parse once at start. Re-parse only when patches actually change
  source.
- Issue 3's compile-output gate (`compiles?(new_src)`) survives
  intact, just moves to operate on the post-patch source.
- `applied_rules` trace shape unchanged: `[{rule, count_or_:reverted}]`.

### Test strategy

Existing tests assert `fix(source, opts) == expected_source`. They
keep working unchanged by routing through a helper:

```elixir
# test/support/rule_helper.ex (new)
def apply_rule(rule, source, opts \\ []) do
  ast = Sourceror.parse_string!(source)
  patches = rule.fix(ast, Keyword.put(opts, :source, source))
  Sourceror.patch_string(source, patches)
end
```

Each rule's test file changes `Rule.fix(source, opts)` calls to
`apply_rule(Rule, source, opts)`. One-line search/replace per file.
**No test assertion changes.** This is what makes the big-bang feasible
within a single PR.

## Migration scope

### Bucket A — 60 rules (round-trip → patches)

These currently do `parse → postwalk → to_string`. Migration: walk
AST, find target nodes, emit `[%{range: Sourceror.get_range(node),
change: Sourceror.to_string(new_subtree, line_length: budget)}]`.

The `line_length: budget` trick from `no_map_then_aggregate` is
recommended via a new `RuleHelpers.render_replacement/2` helper that
picks budget from the original range's width — keeps multi-line
sources from collapsing.

Rules: `avoid_graphemes_enum_count`, `avoid_graphemes_length`,
`hallucinated_guard`, `inconsistent_param_names`,
`no_anon_fn_application_in_pipe`, `no_case_true_false`,
`no_cond_two_clauses`, `no_destructure_reconstruct`,
`no_doc_false_on_private`, `no_double_sort_same_list`,
`no_eager_with_index_in_reduce`, `no_enum_at_midpoint_access`,
`no_enum_count_for_length`, `no_enum_drop_negative`,
`no_enum_take_negative`, `no_explicit_max_reduce`,
`no_explicit_min_reduce`, `no_explicit_sum_reduce`,
`no_grapheme_palindrome_check`, `no_integer_to_string_digits`,
`no_is_prefix_for_non_guard`, `no_kernel_op_in_pipeline`,
`no_kernel_shadowing`, `no_length_based_indexing`,
`no_length_guard_to_pattern`, `no_list_append_in_recursion`,
`no_list_append_in_reduce`, `no_list_fold`, `no_manual_enum_uniq`,
`no_manual_frequencies`, `no_manual_list_last`, `no_manual_max`,
`no_manual_min`, `no_manual_string_reverse`, `no_map_get_sentinel`,
`no_map_keys_enum_lookup`, `no_map_update_then_fetch`,
`no_missing_require_logger`, `no_multiple_enum_at`,
`non_grouped_clauses`, `no_param_rebinding`,
`no_redundant_assignment`, `no_redundant_enum_join_separator`,
`no_redundant_list_traversal`, `no_redundant_negated_guard`,
`no_sort_for_top_k`, `no_sort_then_at`, `no_sort_then_reverse`,
`no_string_length_for_char_check`, `no_take_while_length_check`,
`no_trailing_newline_in_doc`, `no_underscore_function_name`,
`no_unless_else`, `prefer_desc_sort_over_negative_take`,
`prefer_enum_reverse_two`, `prefer_enum_slice`,
`prefer_heredoc_for_multi_line_doc`, `redundant_list_guard`,
`unnecessary_grapheme_chunking`, `use_map_join`.

### Bucket B — 7 rules (regex → AST-walking patches)

These currently use `Regex.replace` on the source string. Migration:
walk AST to find target nodes, emit patches at their ranges.

Rules: `no_guard_equality_for_pattern_match`,
`no_identity_function_in_enum`, `no_is_nil_guard`,
`no_keyword_get_integer_key`, `no_piped_regex_replace`,
`no_redundant_binary_syntax`, `no_unnecessary_catch_all_raise`.

Note: these are the riskiest migrations because the regex approach
sometimes matches things the AST analog wouldn't (e.g.
syntactically-embedded patterns in strings). Verify each rule's test
suite catches the equivalence.

### Bucket C — 3 rules (already patch-based)

Already emit patches. Adapt to the new `fix(ast, opts) → [patch]`
callback signature (move parse out, return patches directly).

Rules: `no_length_comparison_for_empty`,
`no_list_to_tuple_for_access`, `no_map_then_aggregate`.

### Bucket D — 6 rules (mixed shape)

Parse internally but don't always end with `Sourceror.to_string`.
Per-rule audit during migration; most will convert to the same
`walk + emit patches` shape.

Rules: `no_enum_at_negative_index`, `no_identity_float_coercion`,
`no_map_keys_or_values_for_iteration` (largest at 652 LOC),
`no_nested_enum_on_same_enumerable` (already byte-range adjacent),
`no_string_concat_in_loop`, `prefer_erlang_float`.

### Unfixable — 15 rules (check-only)

`fix/2` is no-op (returns source). Migration: `fix(ast, opts) → []`.
Only `check/2` needs review for Sourceror AST shape compatibility
(literal patterns like `n in 0..5` need to handle
`{:__block__, _, [n]}` wrappers).

Rules: `no_enum_at_binary_search`, `no_enum_at_in_loop`,
`no_enum_at_loop_access`, `no_length_in_guard`,
`no_list_append_in_loop`, `no_list_delete_at_in_loop`,
`no_map_as_set`, `no_map_keys_or_values_for_raw_iteration`,
`no_nested_enum_on_same_enumerable_unfixable`,
`no_repeated_enum_traversal`, `no_sort_for_top_k_reduce`,
`no_split_to_count`, `no_string_concat_in_loop_unfixable`,
`prefer_map_fetch_over_has_key`,
`unnecessary_grapheme_chunking_unfixable`.

## Files changed

### Interface
- `lib/pattern/rule.ex` — new `@callback fix/2 :: [patch]`, new
  `@type patch`, drop old string-in/string-out callback.

### Orchestrator
- `lib/pattern.ex` — `run_fixable_rules/3` rewritten per design
  sketch above. `analyze/2` updated to use Sourceror AST.
- `lib/credence.ex` — typespec updates for `applied_rules`.

### Helpers
- `lib/rule_helpers.ex`:
  - `normalize_sourceror_ast/1` already exists — keep for rules
    whose check patterns benefit from the unwrapped shape.
  - Add `render_replacement(new_ast, original_range) :: String.t()` —
    centralizes the `line_length` budget heuristic from
    `no_map_then_aggregate`.

### Rules
- 60 + 7 + 3 + 6 + 15 = **91 files under `lib/pattern/`** rewritten.
  (The 15 unfixable rules need only check shape review.)

### Tests
- `test/support/rule_helper.ex` (new) — `apply_rule/3` wrapper.
- 91 test files in `test/pattern/*_test.exs` — replace direct
  `Rule.fix(source, opts)` calls with `apply_rule(Rule, source, opts)`.
  Mechanical search/replace per file.
- `test/credence_pipeline_test.exs` — update integration tests
  exercising `Pattern.fix_with_trace/2` (interface change), and
  re-verify the `compile-output gate` describe block (Issue 3 still
  passes against the patched-source path).

## Verification

1. **Existing test suite passes.** 3197 tests. Tests use `apply_rule`
   wrapper; their string-equality assertions verify each rule's
   migrated output matches the legacy output byte-for-byte. This is
   the primary safety net.
2. **Issue repros (1-4) still produce correct outputs.** Re-run the
   `Credence.Pattern.NoListToTupleForAccess.fix/2`,
   `Credence.Pattern.NoMapThenAggregate.fix/2`, and
   `Credence.Pattern.NoLengthComparisonForEmpty.fix/2` repros from
   prior turns; byte-identical output expected.
3. **Compile-output gate still fires.** `BrokenFixRule` and
   `UnparseableFixRule` tests in `credence_pipeline_test.exs` keep
   passing — the gate just moves from "after `fix/2` returns" to
   "after `Sourceror.patch_string` applies."
4. **No layout regressions.** Visual diff one realistic file
   (`ex_vrp/lib/ex_vrp/neighbourhood.ex` or similar) before/after; no
   line-collapse or formatting drift in unchanged regions.

## Risks and mitigations

- **Test wrapper hides patch correctness issues** — tests assert on
  assembled source, so a rule that emits wrong patches but happens to
  produce equivalent source still passes. *Mitigation:* spot-check
  patch outputs for a sampling of rules during migration, not just
  the final assembled string.
- **Sourceror AST shape surprises** — `:__block__` wrappers around
  literals/2-tuples break check patterns that expected raw shape.
  *Mitigation:* `RuleHelpers.normalize_sourceror_ast/1` exists for
  rules that need the unwrapped form in check; the alternative is
  pattern-match on the wrapped shape directly.
- **Multi-patch atomicity** — a rule emitting overlapping patches
  fails at `Sourceror.patch_string`. *Mitigation:* document
  non-overlap as a rule invariant; add an orchestrator-side overlap
  detector that logs and reverts (treat like compile failure).
- **15 unfixable check functions may match `{:__block__, _, [literal]}`
  ASTs incorrectly** — comparisons like `n in 0..5` work either way,
  but explicit literal matches like `{:==, _, [_, 1]}` won't fire on
  Sourceror's `{:==, _, [_, {:__block__, _, [1]}]}`. *Mitigation:*
  run all check tests; ones with literal-matching patterns will fail
  loudly.
- **One massive PR** — review and bisect difficulty. *Mitigation:*
  user accepted this trade-off explicitly. Commit-per-rule history
  within the single PR helps bisecting if needed.

## Out of scope

- Semantic phase rules (no AST involvement; stay string-based).
- Syntax phase rules (unparseable input; can't use AST).
- Perf optimization beyond the architectural simplification.
- Adding new rules; existing 91 are the migration set.
