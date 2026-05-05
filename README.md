# Credence

A semantic linter for LLM-generated Elixir code.

Elixir's compiler checks syntax. Credo checks style. Credence checks *semantics* — it catches patterns that compile and pass tests but are non-idiomatic, inefficient, or ported from Python/JavaScript conventions that don't belong in Elixir.

Built for LLM code pipelines. LLMs make the same mistakes every time: `List.foldl` instead of `Enum.reduce`, `Enum.sort |> Enum.take(1)` instead of `Enum.min`, Python-style `_private` function names, defensive catch-all clauses that degrade Elixir's built-in error reporting. Credence catches these at scale and feeds violations back as retry context.

## Installation

```elixir
def deps do
  [{:credence, github: "Cinderella-Man/credence", only: [:dev, :test], runtime: false}]
end
```

## Quick start

```elixir
result = Credence.analyze(File.read!("lib/my_module.ex"))

unless result.valid do
  Enum.each(result.issues, fn issue ->
    IO.puts("#{issue.rule}: #{issue.message}")
  end)
end
```

## LLM pipeline integration

Credence fits as a validation step after `mix compile`, `mix format`, and `mix test`. Feed violations back to the LLM as error context for retry:

```elixir
defmodule Pipeline.SemanticCheck do
  def validate(code) do
    case Credence.analyze(code) do
      %{valid: true} ->
        :ok

      %{issues: issues} ->
        feedback =
          Enum.map_join(issues, "\n", fn issue ->
            "Line #{issue.meta.line}: #{issue.message}"
          end)

        {:error, feedback}
    end
  end
end
```

The feedback string goes straight into your LLM retry prompt. Credence messages include the fix — the LLM gets actionable instructions, not just complaints.

You can also run a subset of rules:

```elixir
Credence.analyze(code, rules: [
  Credence.Rule.NoListAppendInLoop,
  Credence.Rule.NoSortForTopK,
  Credence.Rule.NoListFold
])
```

## Writing custom rules

Every rule implements `Credence.Rule`:

```elixir
defmodule Credence.Rule.MyRule do
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        # pattern match on node, return {node, [issue | issues]} or {node, issues}
      end)

    Enum.reverse(issues)
  end
end
```

Pass custom rules via the `:rules` option or add them to `@default_rules` in `Credence`.

## Rules

| Rule | Description | Auto-fixable |
|------|-------------|:------------:|
| `AvoidGraphemesEnumCount` | `Enum.count/1` on `String.graphemes/1` result — use `String.length/1` instead | ✅ |
| `AvoidGraphemesLength` | `length/1` on `String.graphemes/1` result — use `String.length/1` instead | ✅ |
| `DescriptiveNames` | Single-letter variable names in function signatures | ❌ |
| `InconsistentParamNames` | Same positional parameter uses different names across function clauses | ✅ |
| `NoAnonFnApplicationInPipe` | Anonymous functions applied with `.()` inside a pipe chain | ✅ |
| `NoDestructureReconstruct` | List destructured into variables only to reconstruct the same list | ✅ |
| `NoDocFalseOnPrivate` | `@doc false` on private functions (`defp`) — redundant | ✅ |
| `NoDoubleSortSameList` | Same list sorted twice (ascending then descending) — use `Enum.sort/2` once | ✅ |
| `NoEagerWithIndexInReduce` | `Enum.with_index/1` passed directly into `Enum.reduce` — use `Enum.with_index/2` | ✅ |
| `NoEnumAtBinarySearch` | `Enum.at/2` inside recursive binary search functions — use a tuple/array | ❌ |
| `NoEnumAtInLoop` | `Enum.at/2` inside looping constructs — O(n) per iteration | ❌ |
| `NoEnumAtLoopAccess` | `Enum.at/2` inside loops (heuristic) | ❌ |
| `NoEnumAtMidpointAccess` | `Enum.at/2` with a midpoint index inside divide-and-conquer patterns | ✅ |
| `NoEnumAtNegativeIndex` | Multiple `Enum.at/2` inside a single function - converted to reverse + pattern match | ✅ |
| `NoEnumCountForLength` | `Enum.count/1` without a predicate on a plain list — use `length/1` | ✅ |
| `NoEnumDropNegative` | `Enum.drop(list, -n)` — use `Enum.take/2` instead | ✅ |
| `NoEnumTakeNegative` | `Enum.take(list, -n)` — use `Enum.drop/2` and reverse instead | ✅ |
| `NoExplicitMaxReduce` | Explicit max-reduction pattern inside `Enum.reduce/3` — use `Enum.max/1` | ✅ |
| `NoExplicitMinReduce` | Explicit min-reduction pattern inside `Enum.reduce/3` — use `Enum.min/1` | ✅ |
| `NoExplicitSumReduce` | Explicit sum-reduction pattern inside `Enum.reduce/3` — use `Enum.sum/1` | ✅ |
| `NoGraphemePalindromeCheck` | String palindrome check via `String.graphemes` — use `String.reverse/1` | ✅ |
| `NoGuardEqualityForPatternMatch` | Guard equality check on a parameter that could be a pattern match clause | ✅ |
| `NoIntegerToStringDigits` | `Integer.to_string/1` \|> `String.graphemes/1` — use `Integer.digits/1` | ✅ |
| `NoIsPrefixForNonGuard` | `is_` prefix on non-guard `def`/`defp` functions | ✅ |
| `NoKernelShadowing` | Variables that shadow `Kernel` functions | ❌ |
| `NoLengthGuardToPattern` | `length/1` inside guard clauses - use pattern matching up to 5 elements | ✅ |
| `NoLengthInGuard` | `length/1` inside guard clauses — nest logic instead | ❌ |
| `NoListAppendInLoop` | `++` inside non-fixable looping constructs — O(n²) | ❌ |
| `NoListAppendInRecursion` | `++` inside recursion — O(n²) | ✅ |
| `NoListAppendInReduce` | `++` inside reduce — O(n²) | ✅ |
| `NoListDeleteAtInLoop` | `List.delete_at/2` inside looping constructs | ❌ |
| `NoListFold` | `List.foldl/3` or `List.foldr/3` — use `Enum.reduce/3` | ✅ |
| `NoListLast` | `List.last/1` — use pattern matching or `Enum.at(list, -1)` | ❌ |
| `NoListToTupleForAccess` | `List.to_tuple(list)` only for index access — use `Enum.at/2` | ✅ |
| `NoManualEnumUniq` | Manual uniqueness filtering reimplementing `Enum.uniq/1` | ✅ |
| `NoManualFrequencies` | Manual frequency counting reimplementing `Enum.frequencies/1` | ✅ |
| `NoManualListLast` | Hand-rolled reimplementation of `List.last/1` | ✅ |
| `NoManualMax` | `if` expression reimplementing `Kernel.max/2` | ✅ |
| `NoManualMin` | `if` expression reimplementing `Kernel.min/2` | ✅ |
| `NoManualStringReverse` | Manual string reversal via graphemes — use `String.reverse/1` | ✅ |
| `NoMapAsSet` | `Map` with boolean values used as a set — use `MapSet` | ❌ |
| `NoMapKeysEnumLookup` | `Map.keys/1` piped into an `Enum` lookup — use `Map.has_key?/2` | ✅ |
| `NoMapKeysOrValuesForIteration` | `Map.values/1` or `Map.keys/1` fed into `Enum` iteration — iterate the map directly | ✅ |
| `NoMapKeysOrValuesForRawIteration` | `Map.values/1` or `Map.keys/1` into `Enum` (unfixable variant) | ❌ |
| `NoMapThenAggregate` | `Enum.map/2` immediately followed by a terminal aggregation — use `map_` variant | ✅ |
| `NoMapUpdateThenFetch` | `Map.update/4` or `Map.update!/3` followed by `Map.fetch/get` on the same key | ✅ |
| `NoMultipleEnumAt` | Multiple `Enum.at/2` calls on the same list — convert to tuple | ✅ |
| `NoNestedEnumOnSameEnumerable` | `Enum.member?/2` nested inside another `Enum.*` traversal on the same enumerable | ✅ |
| `NoNestedEnumOnSameEnumerableUnfixable` | Nested `Enum.*` calls on the same enumerable (unfixable variant) | ❌ |
| `NoParamRebinding` | Rebinding parameter names inside a function body | ✅ |
| `NoRedundantEnumJoinSeparator` | `Enum.join(list, "")` — the empty string is the default; omit it | ✅ |
| `NoRedundantNegatedGuard` | Guard clause logically redundant because a preceding clause already handles the case | ✅ |
| `NoRepeatedEnumTraversal` | Same variable traversed multiple times in separate `Enum` calls | ❌ |
| `NoSortForTopK` | Full sort just to take the top-k elements — use `Enum.min_max_by` / `Enum.take` | ✅ |
| `NoSortForTopKReduce` | Full sort for top-k inside a reduce (unfixable variant) | ❌ |
| `NoSortThenAt` | `Enum.sort \|> Enum.at(index)` — use `Enum.min/max` directly | ✅ |
| `NoSortThenAtUnfixable` | `Enum.sort \|> Enum.at` via intermediate variable (unfixable variant) | ❌ |
| `NoSortThenReverse` | `Enum.sort/1` then `Enum.reverse/1` — use `Enum.sort(list, :desc)` | ✅ |
| `NoSortThenReverseUnfixable` | Sort then reverse via intermediate variable (unfixable variant) | ❌ |
| `NoStringConcatInLoop` | `<>` string concatenation inside loops — use `IO.iodata_to_binary` / iodata | ✅ |
| `NoStringConcatInLoopUnfixable` | `<>` string concatenation in complex loops (unfixable variant) | ❌ |
| `NoStringLengthForCharCheck` | `String.length(x) == 1` to check for a single character — use pattern matching | ✅ |
| `NoTakeWhileLengthCheck` | `Enum.take_while/2 \|> length/1` — use `Enum.count/2` with a predicate | ✅ |
| `NoUnderscoreFunctionName` | Leading `_` in function names to indicate privacy — use `defp` instead | ✅ |
| `NoUnnecessaryCatchAllRaise` | Catch-all clause where every argument is a wildcard and the body just raises | ✅ |
| `PreferDescSortOverNegativeTake` | `Enum.sort \|> Enum.take(-n)` — use `Enum.sort(list, :desc) \|> Enum.take(n)` | ✅ |
| `PreferEnumReverseTwo` | `Enum.reverse(list) ++ other` — use `Enum.reverse(list, other)` | ✅ |
| `PreferEnumSlice` | `Enum.drop/2 \|> Enum.take/2` — use `Enum.slice/3` | ✅ |
| `RedundantListGuard` | Redundant `is_list/1` guard on a variable already matched as a list | ✅ |
| `UnnecessaryGraphemeChunking` | N-gram pipeline that converts string to graphemes unnecessarily | ✅ |
| `UnnecessaryGraphemeChunkingUnfixable` | Inefficient grapheme-based string transformation (unfixable variant) | ❌ |
| `UseMapJoin` | `Enum.map/2 \|> Enum.join/1,2` — use `Enum.map_join/3` | ✅ |

## License

MIT