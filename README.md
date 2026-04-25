# Credence

THIS IS VERY EARLY STAGE PROJECT

A semantic linter for Elixir that catches performance anti-patterns and non-idiomatic code by analyzing the AST.

Credence fills the gap between compiler warnings and [Credo](https://github.com/rrrene/credo). Where the compiler checks syntax and Credo checks style, Credence checks *semantics* — it understands what your code is doing and flags patterns that are technically valid but wasteful, confusing, or non-idiomatic in Elixir.

## Why?

Elixir's linked-list data model makes some patterns that look harmless actually expensive. Appending with `++` in a loop is O(n²). Calling `length/1` in a guard traverses the entire list on every clause attempt. Sorting a list twice when you could sort once and reverse. These aren't bugs — they compile, they pass tests — but they're traps, especially for developers coming from languages with array-based lists.

Credence catches 13 of these patterns today, each backed by AST analysis and tested against real-world code from LLM-generated Elixir datasets.

## Installation

Add `credence` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:credence, github: "Cinderella-Man/credence", only: [:dev, :test], runtime: false}
  ]
end
```

Then fetch:

```bash
mix deps.get
```

## Usage

### Programmatic API

```elixir
code = File.read!("lib/my_module.ex")
result = Credence.analyze(code)

if result.valid do
  IO.puts("No issues found")
else
  for issue <- result.issues do
    IO.puts("[#{issue.severity}] #{issue.rule}: #{issue.message} (line #{issue.meta.line})")
  end
end
```

`Credence.analyze/1` returns a map:

```elixir
%{
  valid: false,
  issues: [
    %Credence.Issue{
      rule: :no_list_append_in_loop,
      severity: :high,
      message: "Avoid using '++' inside loops or recursive functions...",
      meta: %{line: 7}
    }
  ]
}
```

### Running a subset of rules

```elixir
Credence.analyze(code, rules: [
  Credence.Rule.NoListAppendInLoop,
  Credence.Rule.NoLengthInGuard
])
```

## Rules

### Performance — High severity

| Rule | What it catches | Fix |
|------|----------------|-----|
| `NoListAppendInLoop` | `acc ++ [item]` inside `Enum.reduce`, `for`, or recursive functions | Prepend with `[item \| acc]` and `Enum.reverse/1` after the loop |

### Performance — Warning severity

| Rule | What it catches | Fix |
|------|----------------|-----|
| `NoLengthInGuard` | `length(list)` in `when` clauses | Pattern match (`[_ \| _]`) or move check to body |
| `NoListLast` | `List.last/1` (O(n) on linked lists) | Restructure algorithm or use `Enum.at(list, -1)` |
| `NoSortThenReverse` | `Enum.sort(x) \|> Enum.reverse()` | `Enum.sort(x, :desc)` |
| `NoDoubleSortSameList` | `Enum.sort(x)` and `Enum.sort(x, :desc)` on the same variable | Sort once, then `Enum.reverse/1` |
| `NoManualStringReverse` | `String.graphemes \|> Enum.reverse \|> Enum.join` | `String.reverse/1` |
| `NoGraphemePalindromeCheck` | Decomposing into graphemes/charlist just to compare with `Enum.reverse` | `str == String.reverse(str)` |

### Readability — Info severity

| Rule | What it catches | Fix |
|------|----------------|-----|
| `NoSortThenAt` | `Enum.sort(x) \|> Enum.at(i)` — full sort for a single element | `Enum.min/1`, `Enum.max/1`, or pattern matching |
| `NoMultipleEnumAt` | 3+ `Enum.at(var, literal)` calls on the same variable | Pattern match: `[a, b, c \| _] = var` |
| `NoStringLengthForCharCheck` | `String.length(x) == 1` | Pattern match: `<<_::utf8>>` |
| `NoRedundantEnumJoinSeparator` | `Enum.join("")` | `Enum.join()` — empty string is the default |
| `NoGuardEqualityForPatternMatch` | `when n == 2` in a guard | Match the literal in the function head: `def f(2, ...)` |
| `NoParamRebinding` | Rebinding `fn` parameter names inside the body | Use a distinct name: `new_q = ...` instead of `q = ...` |

## How it works

Every rule implements the `Credence.Rule` behaviour:

```elixir
@callback check(Macro.t(), keyword()) :: [Credence.Issue.t()]
```

Each rule receives the full AST from `Code.string_to_quoted/1` and walks it with `Macro.prewalk/3`, pattern-matching on the specific node shapes it cares about. Some rules use a single pass (e.g. `NoListLast` just matches `List.last` calls). Others use two passes — first collecting variable bindings, then checking how those variables are used (e.g. `NoDoubleSortSameList` collects sort calls, then checks if the same source variable was sorted both ways).

No macros are expanded. No code is executed. The analysis is purely structural.

## Writing your own rule

```elixir
defmodule Credence.Rule.NoFooBar do
  @moduledoc "Detects calls to FooBar.baz/1."
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:FooBar]}, :baz]}, meta, _} = node, acc ->
          issue = %Issue{
            rule: :no_foo_bar,
            severity: :warning,
            message: "Avoid FooBar.baz/1 — use Qux.baz/1 instead.",
            meta: %{line: Keyword.get(meta, :line)}
          }
          {node, [issue | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end
end
```

Register it by passing it in the `:rules` option or adding it to the `@default_rules` list in `Credence`.

## Origin

Credence was built while working on an LLM-based Python-to-Elixir code translation pipeline. The pipeline uses `mix compile`, `mix format`, `mix credo`, and `mix test` to validate generated code — but those tools miss semantic issues like O(n²) list appends or redundant sorts. Credence adds a fifth validation step that catches these patterns and feeds the violations back to the LLM as error context for retry, resulting in more idiomatic generated code.

The rules were discovered empirically by analyzing patterns across hundreds of LLM-generated Elixir solutions and identifying recurring anti-patterns that the existing toolchain missed.

## License

MIT