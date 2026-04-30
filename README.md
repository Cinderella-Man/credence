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