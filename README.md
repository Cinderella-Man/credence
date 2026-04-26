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
    IO.puts("[#{issue.severity}] #{issue.rule}: #{issue.message}")
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

## Rules

**Performance** — patterns that are technically correct but algorithmically wasteful on linked lists:

- `NoListAppendInLoop` — `acc ++ [item]` in reduce/recursion (O(n²)); prepend and reverse instead
- `NoLengthInGuard` — `length(list)` in guards traverses the full list; pattern match instead
- `NoSortForTopK` — `Enum.sort |> Enum.take(k)`; use `Enum.min`, `Enum.max`, or `Enum.reduce`
- `NoSortThenReverse` — `Enum.sort |> Enum.reverse`; use `Enum.sort(:desc)`
- `NoDoubleSortSameList` — sorting the same list twice; sort once and reverse
- `NoManualStringReverse` — `String.graphemes |> Enum.reverse |> Enum.join`; use `String.reverse`
- `NoListLast` — `List.last/1` is O(n); restructure or use `Enum.at(list, -1)`
- `NoRepeatedEnumTraversal` — multiple passes over the same enumerable
- `NoNestedEnumOnSameEnumerable` — nested Enum calls on the same collection
- `NoMapKeysEnumLookup` — `Map.keys(m) |> Enum.map(fn k -> m[k] ... end)`; iterate the map directly

**Non-idiomatic** — patterns ported from other languages that don't fit Elixir conventions:

- `NoListFold` — `List.foldl/3` or `List.foldr/3`; use `Enum.reduce/3`
- `NoUnderscoreFunctionName` — `defp _helper(...)` (Python convention); use `defp do_helper(...)`
- `NoUnnecessaryCatchAllRaise` — `def foo(_), do: raise(...)` ; let `FunctionClauseError` do its job
- `RedundantListGuard` — `when is_list(tail)` on a cons-pattern variable; already guaranteed
- `NoManualMax` — `if a > b, do: a, else: b`; use `max(a, b)`
- `NoManualMin` — `if a < b, do: a, else: b`; use `min(a, b)`
- `NoExplicitMaxReduce` / `NoExplicitMinReduce` / `NoExplicitSumReduce` — hand-rolled reduce for built-in operations
- `NoGuardEqualityForPatternMatch` — `when n == 2`; match the literal in the function head

**Readability** — patterns that obscure intent:

- `InconsistentParamNames` — same parameter named differently across clauses of the same function
- `DescriptiveNames` — flags single-letter or opaque variable names
- `NoParamRebinding` — rebinding a function parameter name inside the body
- `NoMultipleEnumAt` — 3+ `Enum.at` calls on the same variable; pattern match instead
- `NoStringLengthForCharCheck` — `String.length(x) == 1`; match `<<_::utf8>>`
- `NoRedundantEnumJoinSeparator` — `Enum.join("")`; empty string is the default
- `NoGraphemePalindromeCheck` — grapheme decomposition for palindrome checks; use `String.reverse`
- `UnnecessaryGraphemeChunking` — unnecessary `String.graphemes` usage
- `NoSortThenAt` — full sort to access a single element

## Writing custom rules

Every rule implements `Credence.Rule`:

```elixir
defmodule Credence.Rule.MyRule do
  @behaviour Credence.Rule
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

## License

MIT