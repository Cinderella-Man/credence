defmodule Credence.Pattern.NoAnonFnApplicationInPipe do
  @moduledoc """
  Readability rule: Detects anonymous functions applied with `.()` inside
  a pipeline.

  Applying an anonymous function directly in a pipe (e.g.
  `|> (fn x -> ... end).()`) is non-idiomatic and hard to read.
  Use `then/2` instead, which was added in Elixir 1.12 specifically
  for this purpose.

  ## Bad

      list
      |> Enum.sort()
      |> (fn s -> [1 | s] end).()

  ## Good

      list
      |> Enum.sort()
      |> then(fn s -> [1 | s] end)

      # Or with capture syntax:
      |> then(&[1 | &1])
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match: ... |> (fn ... end).()
        {:|>, meta, [_left, {{:., _, [{:fn, _, _}]}, _, _args}]} = node, issues ->
          issue = %Issue{
            rule: :no_anon_fn_application_in_pipe,
            message:
              "Avoid applying anonymous functions with `.()` inside a pipeline. " <>
                "Use `then/2` instead: `|> then(fn x -> ... end)`.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # |> (fn ... end).() → |> then(fn ... end)
      {:|>, pipe_meta, [left, {{:., _, [{:fn, _, _} = fn_node]}, _, _args}]} ->
        {:|>, pipe_meta, [left, {:then, [], [fn_node]}]}

      node ->
        node
    end)
    |> Sourceror.to_string()
  end
end
