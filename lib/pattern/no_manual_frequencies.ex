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

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.reduce(list, %{}, fn ... -> Map.update(...) end)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, {:%{}, _, []}, body]} =
            node,
        issues ->
          if is_simple_frequency_fn?(body) do
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
          if is_simple_frequency_fn?(body) do
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
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Piped: list |> Enum.reduce(%{}, fn ... end) → Enum.frequencies(list)
      {:|>, _,
       [
         list,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, body]}
       ]} = node ->
        if is_simple_frequency_fn?(body) do
          enum_frequencies_call(list)
        else
          node
        end

      # Direct: Enum.reduce(list, %{}, fn ... end) → Enum.frequencies(list)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [list, {:%{}, _, []}, body]} = node ->
        if is_simple_frequency_fn?(body) do
          enum_frequencies_call(list)
        else
          node
        end

      node ->
        node
    end)
  end

  defp enum_frequencies_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies]}, [], [enum]}
  end

  # Sourceror wraps literals in {:__block__, _, [value]}
  defp unwrap_literal({:__block__, _, [val]}), do: val
  defp unwrap_literal(val), do: val

  # Verifies the fn is a simple frequency-counting function:
  # 1. The Map.update key must be the reduce's element parameter (not a derived value)
  # 2. No conditional logic wrapping the Map.update (would mean filtered counts)
  defp is_simple_frequency_fn?(fn_expr) do
    case fn_expr do
      {:fn, _, [{:->, _, [params, body_block]}]} when length(params) == 2 ->
        element_param = hd(params)
        has_matching_map_update?(body_block, element_param) and not has_conditional?(body_block)

      _ ->
        false
    end
  end

  defp has_matching_map_update?(body_block, expected_key) do
    {_ast, found} =
      Macro.prewalk(body_block, false, fn
        # Map.update(acc, key, 1, increment_fn) — the `1` default is the
        # hallmark of frequency counting. Key must match the element param.
        {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [_, key, default, _]} = node, _ ->
          if unwrap_literal(default) == 1 and keys_match?(key, expected_key) do
            {node, true}
          else
            {node, false}
          end

        # Map.update!(acc, key, increment_fn) — key must match the element param.
        {{:., _, [{:__aliases__, _, [:Map]}, :update!]}, _, [_, key, _]} = node, _ ->
          if keys_match?(key, expected_key) do
            {node, true}
          else
            {node, false}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp has_conditional?(body_block) do
    {_ast, found} =
      Macro.prewalk(body_block, false, fn
        {:if, _, _} = node, _ -> {node, true}
        {:case, _, _} = node, _ -> {node, true}
        {:cond, _, _} = node, _ -> {node, true}
        {:unless, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp keys_match?(key_ast, param_ast) do
    extract_var_name(key_ast) == extract_var_name(param_ast) and extract_var_name(key_ast) != nil
  end

  defp extract_var_name({:__block__, _, [val]}), do: extract_var_name(val)
  defp extract_var_name({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: name
  defp extract_var_name(_), do: nil

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
