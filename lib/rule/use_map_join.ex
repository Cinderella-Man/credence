defmodule Credence.Rule.UseMapJoin do
  @moduledoc """
  Detects `Enum.map/2` chained into `Enum.join/1` or `Enum.join/2`,
  and suggests `Enum.map_join/3` instead.

  ## Why this matters

  `Enum.map/2` followed by `Enum.join` creates a throwaway intermediate
  list.  `Enum.map_join/3` maps and joins in a single pass with no
  intermediate allocation:

      # Flagged — intermediate list
      list
      |> Enum.map(&to_string/1)
      |> Enum.join(", ")

      # Idiomatic — single pass
      Enum.map_join(list, ", ", &to_string/1)

  LLMs generate the two-step version frequently because they decompose
  "transform then combine" into separate operations.

  ## Flagged patterns

  - `Enum.map(enum, f) |> Enum.join()` (pipeline, any separator)
  - `Enum.join(Enum.map(enum, f))` (nested call)
  - Longer pipelines where map and join are adjacent steps

  Only **adjacent** map→join is flagged.  Intervening steps like
  `Enum.map(f) |> Enum.filter(g) |> Enum.join()` are left alone.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline form: ... |> Enum.map(...) |> Enum.join(...)
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :join) and
               remote_call?(rightmost(left), :Enum, :map) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Nested call form: Enum.join(Enum.map(...), ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta,
         [{{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _} | _rest]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # In a pipeline `a |> b |> c`, the AST is nested as
  # {:|>, _, [{:|>, _, [a, b]}, c]}.  `rightmost` extracts `b` —
  # the step immediately before the current right-hand side.
  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :use_map_join,
      message: """
      `Enum.map/2` piped into `Enum.join` creates an intermediate list.

      Use `Enum.map_join/3` for a single-pass operation:

          Enum.map_join(enumerable, separator, mapper_fn)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
