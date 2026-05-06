# Credence

A semantic linter for LLM-generated Elixir code.

Elixir's compiler checks syntax. Credo checks style. Credence checks *semantics* — it catches patterns that compile and pass tests but are non-idiomatic, inefficient, or ported from Python/JavaScript conventions that don't belong in Elixir.

## Three-phase pipeline

Credence runs code through three escalating phases:

```
Credence.Syntax    → can the parser read it?     (string-level fixes)
Credence.Semantic  → does the compiler accept it? (compiler warning fixes)
Credence.Pattern   → is it idiomatic Elixir?      (80+ AST-level rules)
```

**Syntax** repairs code that won't parse — e.g. `n * (n + 1) div 2` (Python's `//` translated as infix) becomes `div(n * (n + 1), 2)`.

**Semantic** captures compiler warnings via `Code.with_diagnostics/1` and fixes them — unused variables get `_` prefixed, undefined function calls get corrected.

**Pattern** detects and auto-fixes 80+ anti-patterns using AST analysis — `Enum.sort |> Enum.reverse` becomes `Enum.sort(:desc)`, manual frequency counting becomes `Enum.frequencies/1`, `acc ++ [x]` becomes `[x | acc]`.

Each phase has its own `Rule` behaviour. Rules are discovered automatically and run in priority order.

## Installation

```elixir
def deps do
  [{:credence, github: "Cinderella-Man/credence", only: [:dev, :test], runtime: false}]
end
```

## Usage

**Analyze** — detect issues without modifying code:

```elixir
%{valid: true, issues: []} = Credence.analyze(code)
```

**Fix** — auto-fix what's fixable, report the rest:

```elixir
%{code: fixed, issues: remaining} = Credence.fix(code)
```

### Example

```elixir
code = ~S"""
defmodule StudentAnalyzer do
  @doc "Analyzes scores.\nReturns statistics.\n"

  def analyze(scores) do
    if length(scores) == 0 do
      %{error: "no scores"}
    else
      total = Enum.map(scores, fn s -> s end) |> Enum.sum()
      avg = total / Enum.count(scores) * 1.0
      freq = Enum.reduce(scores, %{}, fn s, acc ->
        Map.update(acc, s, 1, &(&1 + 1))
      end)
      ranked = Enum.sort(scores) |> Enum.reverse()
      top_3 = Enum.sort(scores) |> Enum.take(-3)
      unique = scores |> Enum.uniq_by(fn s -> s end)
      csv = Enum.map(unique, fn s -> Integer.to_string(s) end) |> Enum.join(",")

      %{average: avg, frequencies: freq, top_3: top_3,
        csv: csv, passing: is_passing(avg)}
    end
  end

  def is_passing(avg), do: avg |> Kernel.>=(60.0)
end
"""

%{code: fixed, issues: remaining} = Credence.fix(code)
```

15 transformations in one call:

| Before | After |
|--------|-------|
| `@doc "...\n...\n"` | `@doc """` heredoc |
| `length(scores) == 0` | `scores == []` |
| `Enum.map(fn s -> s end) \|> Enum.sum()` | `Enum.sum(scores)` |
| `Enum.count(scores) * 1.0` | `length(scores)` |
| `Enum.reduce(... Map.update ...)` | `Enum.frequencies(scores)` |
| `Enum.sort() \|> Enum.reverse()` | `Enum.sort(:desc)` |
| `Enum.sort() \|> Enum.take(-3)` | `Enum.sort(:desc) \|> Enum.take(3)` |
| `Enum.uniq_by(fn s -> s end)` | `Enum.uniq()` |
| `Enum.map() \|> Enum.join()` | `Enum.map_join()` |
| `is_passing` | `passing?` |
| `Kernel.>=(60.0)` | `avg >= 60.0` |
| `acc ++ [x]` | `[x \| acc]` |
| `@doc false` on `defp` | removed |

## LLM pipeline integration

Credence fits as a validation step after `mix compile`, `mix format`, and `mix test`. Feed violations back to the LLM as retry context:

```elixir
defmodule Pipeline.SemanticCheck do
  def validate(code) do
    case Credence.analyze(code) do
      %{valid: true} -> :ok
      %{issues: issues} ->
        feedback = Enum.map_join(issues, "\n", fn issue ->
          "Line #{issue.meta.line}: #{issue.message}"
        end)
        {:error, feedback}
    end
  end
end
```

You can run a subset of rules:

```elixir
Credence.analyze(code, rules: [
  Credence.Pattern.NoListAppendInRecursion,
  Credence.Pattern.NoSortForTopK,
  Credence.Pattern.NoListFold
])
```

## Writing custom rules

Each phase has its own `Rule` behaviour:

### Pattern rules (AST-level)

```elixir
defmodule Credence.Pattern.MyRule do
  use Credence.Pattern.Rule

  @impl true
  def priority, do: 500  # default; lower runs first

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        # pattern match on node
        {node, issues}
      end)
    Enum.reverse(issues)
  end

  @impl true
  def fixable?, do: true

  @impl true
  def fix(source, _opts) do
    # return modified source string
    source
  end
end
```

### Syntax rules (string-level, for unparseable code)

```elixir
defmodule Credence.Syntax.MyFix do
  use Credence.Syntax.Rule

  @impl true
  def analyze(source), do: []  # return [%Issue{}] for detected problems

  @impl true
  def fix(source), do: source  # return repaired source string
end
```

### Semantic rules (compiler warning fixes)

```elixir
defmodule Credence.Semantic.MyFix do
  use Credence.Semantic.Rule

  @impl true
  def match?(%{severity: :warning, message: msg}), do: false

  @impl true
  def to_issue(diagnostic), do: %Credence.Issue{rule: :my_fix, message: diagnostic.message, meta: %{}}

  @impl true
  def fix(source, diagnostic), do: source
end
```

## Rules

### Syntax rules

| Rule | Description |
|------|-------------|
| `FixDivRem` | `expr div expr` / `expr rem expr` infix syntax → `div(expr, expr)` function call |

### Semantic rules

| Rule | Description |
|------|-------------|
| `UnusedVariable` | Prefixes unused variables with `_` to satisfy `--warnings-as-errors` |
| `UndefinedFunction` | Known corrections — e.g. `Enum.last/1` → `List.last/1` |

### Pattern rules

| Rule | Description | Fix |
|------|-------------|:---:|
| `AvoidGraphemesEnumCount` | `Enum.count(String.graphemes(s))` → `String.length(s)` | ✅ |
| `AvoidGraphemesLength` | `length(String.graphemes(s))` → `String.length(s)` | ✅ |
| `InconsistentParamNames` | Same positional parameter uses different names across clauses | ✅ |
| `NoAnonFnApplicationInPipe` | Anonymous functions applied with `.()` inside a pipe chain | ✅ |
| `NoDestructureReconstruct` | List destructured into variables only to reconstruct the same list | ✅ |
| `NoDocFalseOnPrivate` | `@doc false` on `defp` — redundant | ✅ |
| `NoDoubleSortSameList` | Same list sorted twice — use `Enum.sort/2` once | ✅ |
| `NoEagerWithIndexInReduce` | `Enum.with_index` into `Enum.reduce` — use `Stream.with_index` | ✅ |
| `NoEnumAtBinarySearch` | `Enum.at/2` inside recursive binary search | ❌ |
| `NoEnumAtInLoop` | `Enum.at/2` inside looping constructs — O(n) per iteration | ❌ |
| `NoEnumAtLoopAccess` | `Enum.at/2` inside loops (heuristic) | ❌ |
| `NoEnumAtMidpointAccess` | `Enum.at/2` with midpoint index in divide-and-conquer | ✅ |
| `NoEnumAtNegativeIndex` | `Enum.at(list, -n)` → reverse + pattern match or `List.last` | ✅ |
| `NoEnumCountForLength` | `Enum.count/1` without predicate on list → `length/1` | ✅ |
| `NoEnumDropNegative` | `Enum.drop(list, -n)` → `Enum.take/2` | ✅ |
| `NoEnumTakeNegative` | `Enum.take(list, -n)` → `Enum.drop/2` and reverse | ✅ |
| `NoExplicitMaxReduce` | Manual max-reduce → `Enum.max/1` | ✅ |
| `NoExplicitMinReduce` | Manual min-reduce → `Enum.min/1` | ✅ |
| `NoExplicitSumReduce` | Manual sum-reduce → `Enum.sum/1` | ✅ |
| `NoGraphemePalindromeCheck` | Grapheme palindrome check → `String.reverse/1` | ✅ |
| `NoGuardEqualityForPatternMatch` | Guard equality → pattern match clause | ✅ |
| `NoIdentityFunctionInEnum` | `Enum._by(fn x -> x end)` → non-`_by` variant | ✅ |
| `NoIntegerToStringDigits` | `Integer.to_string \|> String.graphemes` → `Integer.digits` | ✅ |
| `NoIsPrefixForNonGuard` | `is_` prefix on non-guard functions → `?` suffix | ✅ |
| `NoKernelOpInPipeline` | `Kernel.op/2` in pipeline → infix operator | ✅ |
| `NoKernelShadowing` | Variables that shadow `Kernel` functions | ❌ |
| `NoLengthComparisonForEmpty` | `length(list) == 0` → `list == []` | ✅ |
| `NoLengthGuardToPattern` | `length/1` in guard → pattern match up to 5 elements | ✅ |
| `NoLengthInGuard` | `length/1` in guard clauses — nest logic instead | ❌ |
| `NoListAppendInLoop` | `++` inside non-fixable loops — O(n²) | ❌ |
| `NoListAppendInRecursion` | `++` inside recursion — O(n²) | ✅ |
| `NoListAppendInReduce` | `++` inside reduce — O(n²) | ✅ |
| `NoListDeleteAtInLoop` | `List.delete_at/2` inside loops | ❌ |
| `NoListFold` | `List.foldl/3` / `List.foldr/3` → `Enum.reduce/3` | ✅ |
| `NoListLast` | `List.last/1` — use pattern matching or restructure | ❌ |
| `NoListToTupleForAccess` | `List.to_tuple` for index access → `Enum.at/2` | ✅ |
| `NoManualEnumUniq` | Manual uniqueness filtering → `Enum.uniq/1` | ✅ |
| `NoManualFrequencies` | Manual frequency counting → `Enum.frequencies/1` | ✅ |
| `NoManualListLast` | Hand-rolled `List.last/1` reimplementation | ✅ |
| `NoManualMax` | `if` reimplementing `Kernel.max/2` | ✅ |
| `NoManualMin` | `if` reimplementing `Kernel.min/2` | ✅ |
| `NoManualStringReverse` | Manual string reversal → `String.reverse/1` | ✅ |
| `NoMapAsSet` | `Map` with boolean values → `MapSet` | ❌ |
| `NoMapKeysEnumLookup` | `Map.keys \|> Enum.member?` → `Map.has_key?/2` | ✅ |
| `NoMapKeysOrValuesForIteration` | `Map.values/keys` into `Enum` → iterate map directly | ✅ |
| `NoMapKeysOrValuesForRawIteration` | `Map.values/keys` into `Enum` (unfixable) | ❌ |
| `NoMapThenAggregate` | `Enum.map \|> Enum.sum/min/max` → fused variant | ✅ |
| `NoMapUpdateThenFetch` | `Map.update` then `Map.fetch` on same key | ✅ |
| `NoMultipleEnumAt` | Multiple `Enum.at` on same list → convert to tuple | ✅ |
| `NoMultiplyByOnePointZero` | `expr * 1.0` → remove no-op | ✅ |
| `NoNestedEnumOnSameEnumerable` | `Enum.member?` nested in `Enum.*` on same enumerable | ✅ |
| `NoNestedEnumOnSameEnumerableUnfixable` | Nested `Enum.*` on same enumerable (unfixable) | ❌ |
| `NoParamRebinding` | Rebinding parameter names inside function body | ✅ |
| `NoRedundantEnumJoinSeparator` | `Enum.join(list, "")` → `Enum.join(list)` | ✅ |
| `NoRedundantNegatedGuard` | Redundant guard clause already handled by preceding clause | ✅ |
| `NoRepeatedEnumTraversal` | Same variable traversed multiple times in `Enum` calls | ❌ |
| `NoSortForTopK` | Full sort for top-k → `Enum.min/max` | ✅ |
| `NoSortForTopKReduce` | Full sort for top-k in reduce (unfixable) | ❌ |
| `NoSortThenAt` | `Enum.sort \|> Enum.at(0/-1)` → `Enum.min/max` | ✅ |
| `NoSortThenAtUnfixable` | `Enum.sort \|> Enum.at` via intermediate variable | ❌ |
| `NoSortThenReverse` | `Enum.sort \|> Enum.reverse` → `Enum.sort(:desc)` | ✅ |
| `NoSortThenReverseUnfixable` | Sort then reverse via intermediate variable | ❌ |
| `NoSplitToCount` | `length(String.split(str, sep)) - 1` — Python `str.count()` | ❌ |
| `NoStringConcatInLoop` | `<>` in loops → iodata | ✅ |
| `NoStringConcatInLoopUnfixable` | `<>` in complex loops (unfixable) | ❌ |
| `NoStringLengthForCharCheck` | `String.length(x) == 1` → pattern match | ✅ |
| `NoTakeWhileLengthCheck` | `Enum.take_while \|> length` → `Enum.count/2` | ✅ |
| `NoTrailingNewlineInDoc` | Trailing `\n` in `@doc`/`@moduledoc` | ✅ |
| `NoUnderscoreFunctionName` | Leading `_` in function names → `defp` | ✅ |
| `NoUnnecessaryCatchAllRaise` | Catch-all clause that just raises | ✅ |
| `PreferDescSortOverNegativeTake` | `Enum.sort \|> Enum.take(-n)` → `Enum.sort(:desc) \|> Enum.take(n)` | ✅ |
| `PreferEnumReverseTwo` | `Enum.reverse(list) ++ other` → `Enum.reverse(list, other)` | ✅ |
| `PreferEnumSlice` | `Enum.drop \|> Enum.take` → `Enum.slice/3` | ✅ |
| `PreferHeredocForMultiLineDoc` | Multi-line `@doc` with `\n` escapes → heredoc `"""` | ✅ |
| `PreferMapFetchOverHasKey` | `Map.has_key?` in conditions → `Map.fetch/2` | ❌ |
| `RedundantListGuard` | Redundant `is_list/1` guard on pattern-matched list | ✅ |
| `UnnecessaryGraphemeChunking` | N-gram pipeline via unnecessary grapheme conversion | ✅ |
| `UnnecessaryGraphemeChunkingUnfixable` | Grapheme-based string transformation (unfixable) | ❌ |
| `UseMapJoin` | `Enum.map \|> Enum.join` → `Enum.map_join/3` | ✅ |

## License

MIT