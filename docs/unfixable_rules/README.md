# Archived: unfixable rules

This folder holds 15 Pattern rules and their test files that were previously
compiled into the main Credence application. They were moved out of
`lib/pattern/` and `test/pattern/` to reflect a project stance:

> **Every Credence rule either fixes the issue it detects, or it doesn't exist.**
> "Warn but don't fix" is no longer a supported mode.

## Why these rules were removed

Each rule here detects a real anti-pattern, but the fix is one of:

1. **Non-local restructuring** — the cure isn't a single-expression rewrite.
   The flagged code is a *symptom* of a structural issue that touches
   multiple sites (variable initialisation, recursive function signatures,
   accumulator shape across a loop).

2. **Ambiguous remedy** — multiple valid fixes exist, and the right one
   depends on intent the tool can't infer (raise vs. return error tuple,
   inline vs. extract, etc.).

3. **Shape-changing transformation** — applying the "natural" fix would
   silently change the function's return type or element shape.

4. **Companion-of-a-fixable-rule** — these existed specifically to flag
   the residual cases that a narrower fixable rule deliberately skipped.
   Without "warn-only" mode, that role goes away.

## What's still in the main project

- `lib/pattern/` — rules that auto-fix the issues they detect.
- `test/pattern/` — tests for those rules.

The rules in this folder are kept as reference material so future work can
re-introduce them once a fix strategy is decided (e.g., introducing a
companion fixable rule that handles a specific sub-case, then the
flagged-only behaviour can return as a check inside that rule).

## Contents

| File | Original anti-pattern | Reason archived |
|---|---|---|
| `no_enum_at_binary_search.ex` | `Enum.at` inside recursive binary search | Non-local: recursion signature change |
| `no_enum_at_in_loop.ex` | `Enum.at` inside `Enum.reduce`/`map`/`for` | Non-local: need outer-scope tuple conversion |
| `no_enum_at_loop_access.ex` | `Enum.at` inside any loop (heuristic) | Heuristic-only; ambiguous remedy |
| `no_length_in_guard.ex` | `length/1` in `when` guard, non-trivial cases | Ambiguous remedy |
| `no_list_append_in_loop.ex` | `++` inside `for` / non-`reduce` loops | Non-local: accumulator restructure |
| `no_list_delete_at_in_loop.ex` | `List.delete_at` inside loops | Non-local: algorithm change |
| `no_map_as_set.ex` | `Map.put(m, k, true)` as boolean membership | Data-flow: cross-site refactor |
| `no_map_keys_or_values_for_raw_iteration.ex` | `Map.values \|> Enum.chunk_every`, `zip`, etc. | Return-shape would change |
| `no_nested_enum_on_same_enumerable_unfixable.ex` | Residual nested-Enum cases not handled by the fixable variant | Companion-only |
| `no_repeated_enum_traversal.ex` | `Enum.max + Enum.min + Enum.count` on same list | Ambiguous remedy |
| `no_sort_for_top_k_reduce.ex` | `Enum.sort \|> Enum.take(k)` for k > 1 | Non-local: track-top-k state across reduce |
| `no_split_to_count.ex` | `length(String.split(...)) - 1` for counting | Ambiguous remedy (graphemes vs. binary matches) |
| `no_string_concat_in_loop_unfixable.ex` | Residual `<>` in `reduce_while` / multi-generator `for` | Companion-only |
| `prefer_map_fetch_over_has_key.ex` | `if Map.has_key?(m, k), do: m[k]` double lookup | Ambiguous remedy: structural change |
| `unnecessary_grapheme_chunking_unfixable.ex` | Residual chunking variants with `:trim`, custom maps | Companion-only / return-shape risk |
