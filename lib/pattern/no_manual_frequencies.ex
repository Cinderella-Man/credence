defmodule Credence.Pattern.NoManualFrequencies do
  @moduledoc """
  Readability rule: Detects manual frequency counting with
  `Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, x, 1, ...) end)`.

  `Enum.frequencies/1` (available since Elixir 1.10) does exactly this in a
  single, optimized call.

  Also detects derived-key frequency counting where a local variable is used
  as the Map.update key instead of the element parameter:

      Enum.reduce(list, %{}, fn x, acc ->
        key = transform(x)
        Map.update(acc, key, 1, &(&1 + 1))
      end)

  This can be replaced with `Enum.frequencies_by/2` (Elixir 1.13+).

  ## Bad

      list
      |> Enum.reduce(%{}, fn item, counts ->
        Map.update(counts, item, 1, &(&1 + 1))
      end)

      list
      |> Enum.reduce(%{}, fn item, counts ->
        key = transform(item)
        Map.update(counts, key, 1, &(&1 + 1))
      end)

  ## Good

      Enum.frequencies(list)

      Enum.frequencies_by(list, fn item -> transform(item) end)
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
          cond do
            is_simple_frequency_fn?(body) ->
              {node, [build_issue(meta, :frequencies) | issues]}

            is_frequencies_by_fn?(body) ->
              {node, [build_issue(meta, :frequencies_by) | issues]}

            true ->
              {node, issues}
          end

        # Piped: list |> Enum.reduce(%{}, fn ... -> Map.update(...) end)
        {:|>, meta,
         [
           _,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, body]}
         ]} = node,
        issues ->
          cond do
            is_simple_frequency_fn?(body) ->
              {node, [build_issue(meta, :frequencies) | issues]}

            is_frequencies_by_fn?(body) ->
              {node, [build_issue(meta, :frequencies_by) | issues]}

            true ->
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
      # Piped: list |> Enum.reduce(%{}, fn ... end)
      {:|>, _,
       [
         list,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, body]}
       ]} = node ->
        cond do
          is_simple_frequency_fn?(body) ->
            enum_frequencies_call(list)

          true ->
            case frequencies_by_fix(list, body) do
              nil -> node
              fixed -> fixed
            end
        end

      # Direct: Enum.reduce(list, %{}, fn ... end)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [list, {:%{}, _, []}, body]} = node ->
        cond do
          is_simple_frequency_fn?(body) ->
            enum_frequencies_call(list)

          true ->
            case frequencies_by_fix(list, body) do
              nil -> node
              fixed -> fixed
            end
        end

      node ->
        node
    end)
  end

  defp enum_frequencies_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies]}, [], [enum]}
  end

  defp frequencies_by_fix(list, body) do
    case body do
      {:fn, _, [{:->, _, [params, body_block]}]} when length(params) == 2 ->
        element_param = hd(params)

        case body_block do
          {:__block__, _, [binding, map_update]} ->
            if is_derived_frequency_binding?(binding, map_update, element_param) and
                 not has_conditional?(body_block) do
              {:=, _, [_var, derivation_expr]} = binding
              clean_expr = unwrap_literal(derivation_expr)
              transform_fn = {:fn, [], [{:->, [], [[element_param], clean_expr]}]}

              {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies_by]}, [],
               [list, transform_fn]}
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp is_frequencies_by_fn?(fn_expr) do
    case fn_expr do
      {:fn, _, [{:->, _, [params, {:__block__, _, [binding, map_update]} = body_block]}]}
      when length(params) == 2 ->
        element_param = hd(params)

        is_derived_frequency_binding?(binding, map_update, element_param) and
          not has_conditional?(body_block)

      _ ->
        false
    end
  end

  defp is_derived_frequency_binding?(binding, map_update, element_param) do
    case binding do
      {:=, _, [{var_name, _, nil}, expr]} when is_atom(var_name) ->
        references_param?(expr, element_param) and
          is_frequency_map_update_with_var?(map_update, var_name)

      _ ->
        false
    end
  end

  defp is_frequency_map_update_with_var?(ast, var_name) do
    case ast do
      {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [_, key, default, _]} ->
        unwrap_literal(default) == 1 and extract_var_name(key) == var_name

      {{:., _, [{:__aliases__, _, [:Map]}, :update!]}, _, [_, key, _]} ->
        extract_var_name(key) == var_name

      _ ->
        false
    end
  end

  defp references_param?(ast, param) do
    param_name = extract_var_name(param)

    {_ast, found} =
      Macro.prewalk(ast, false, fn
        node, acc ->
          if extract_var_name(node) == param_name do
            {node, true}
          else
            {node, acc}
          end
      end)

    found
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

  defp build_issue(meta, variant) do
    message =
      case variant do
        :frequencies ->
          "Manual frequency counting with `Enum.reduce/3` + `Map.update/4` and an empty map " <>
            "can be replaced with `Enum.frequencies/1`, which is clearer and optimized."

        :frequencies_by ->
          "Manual frequency counting with a derived key using `Enum.reduce/3` + `Map.update/4` " <>
            "can be replaced with `Enum.frequencies_by/2`, which is clearer and optimized."
      end

    %Issue{
      rule: :no_manual_frequencies,
      message: message,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
