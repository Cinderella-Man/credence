defmodule Credence.Pattern.NoManualFrequencies do
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

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.reduce(list, %{}, fn ... -> Map.update(...) end)
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

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Piped: list |> Enum.reduce(%{}, fn ... end) → Enum.frequencies(list)
      {:|>, _,
       [
         list,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, body]}
       ]} = node ->
        if body_has_map_update?(body) do
          enum_frequencies_call(list)
        else
          node
        end

      # Direct: Enum.reduce(list, %{}, fn ... end) → Enum.frequencies(list)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [list, {:%{}, _, []}, body]} = node ->
        if body_has_map_update?(body) do
          enum_frequencies_call(list)
        else
          node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  defp enum_frequencies_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies]}, [], [enum]}
  end

  # Sourceror wraps literals in {:__block__, _, [value]}
  defp unwrap_literal({:__block__, _, [val]}), do: val
  defp unwrap_literal(val), do: val

  defp body_has_map_update?(body) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        # Map.update(acc, key, 1, increment_fn) — the `1` default is the
        # hallmark of frequency counting.
        {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [_, _, default, _]} = node, _ ->
          if unwrap_literal(default) == 1, do: {node, true}, else: {node, false}

        # Map.update!(acc, key, increment_fn)
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
