defmodule Credence.Rule.NoManualFrequencies do
  @moduledoc """
  Readability rule: Detects manual frequency counting with
  `Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, x, 1, ...) end)`.

  `Enum.frequencies/1` (available since Elixir 1.10) does exactly this in a
  single, optimized call.

  ## Bad

      list
      |> Enum.reduce(%{}, fn item, counts ->
        Map.update(counts, item, 1, &(&1 + 1))
      end)

  ## Good

      Enum.frequencies(list)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Enum.reduce(list, %{}, fn ... -> Map.update(...) end)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, {:%{}, _, []}, body]} =
            node,
        issues ->
          if body_has_map_update?(body) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Piped: list |> Enum.reduce(%{}, fn ... -> Map.update(...) end)
        {:|>, meta,
         [
           _,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, body]}
         ]} = node,
        issues ->
          if body_has_map_update?(body) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp body_has_map_update?(body) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        # Map.update(acc, key, 1, increment_fn) — the `1` default is the
        # hallmark of frequency counting. Group-by patterns use a list
        # like [item] as the default, which we must not flag.
        {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [_, _, 1, _]} = node, _ ->
          {node, true}

        # Map.update!(acc, key, increment_fn) — only used on pre-seeded maps,
        # still a frequency pattern when inside reduce with %{}
        {{:., _, [{:__aliases__, _, [:Map]}, :update!]}, _, [_, _, _]} = node, _ ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_frequencies,
      message:
        "Manual frequency counting with `Enum.reduce/3` + `Map.update/4` and an empty map " <>
          "can be replaced with `Enum.frequencies/1`, which is clearer and optimized.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
