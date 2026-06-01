defmodule Credence.Pattern.NoMapPutGetIncrement do
  @moduledoc """
  Detects `Map.put(map, key, Map.get(map, key, 0) + 1)` and rewrites
  to `Map.update(map, key, 1, &(&1 + 1))`.

  `Map.update/4` exists precisely for "update a value or insert a default"
  and avoids the redundant `Map.get` lookup. The +1 variant is by far the
  most common — it is the building block of manual frequency counting.

  ## Bad

      Map.put(counts, char, Map.get(counts, char, 0) + 1)

  ## Good

      Map.update(counts, char, 1, &(&1 + 1))

  ## Auto-fix

  `Map.put(m, k, Map.get(m, k, 0) + 1)` → `Map.update(m, k, 1, &(&1 + 1))`
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, acc ->
          if map_put_get_increment?(node) do
            {node, [build_issue(meta_of(node)) | acc]}
          else
            {node, acc}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      node ->
        case match_put_get_increment(node) do
          {:ok, map, key, default, increment} ->
            if piped?(node) do
              {:|>, [], [map, build_map_update_call(key, default, increment)]}
            else
              build_map_update(map, key, default, increment)
            end

          :no_match ->
            node
        end
    end)
  end

  defp piped?({:|>, _, _}), do: true
  defp piped?(_), do: false

  # Detects: Map.put(m, k, Map.get(m, k, 0) + 1)  and  m |> Map.put(k, Map.get(m, k, 0) + 1)
  defp map_put_get_increment?(node) do
    match?({:ok, _, _, _, _}, match_put_get_increment(node))
  end

  # Direct call: Map.put(m, k, Map.get(m, k, 0) + 1)
  defp match_put_get_increment(
         {{:., _, [{:__aliases__, _, [:Map]}, :put]}, _,
          [map, key, {:+, _, [get_call, increment]}]}
       ) do
    verify_get_increment(map, key, get_call, increment)
  end

  # Piped form: m |> Map.put(k, Map.get(m, k, 0) + 1)
  defp match_put_get_increment(
         {:|>, _,
          [map, {{:., _, [{:__aliases__, _, [:Map]}, :put]}, _,
            [key, {:+, _, [get_call, increment]}]}]}
       ) do
    verify_get_increment(map, key, get_call, increment)
  end

  defp match_put_get_increment(_), do: :no_match

  defp verify_get_increment(map, key, get_call, increment) do
    case get_call do
      {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [map2, key2, default]} ->
        if maps_match?(map, map2) and keys_match?(key, key2) and unwrap_literal(default) == 0 do
          {:ok, map, key, default, unwrap_literal(increment)}
        else
          :no_match
        end

      _ ->
        :no_match
    end
  end

  defp maps_match?(a, b), do: extract_var_name(a) == extract_var_name(b)
  defp keys_match?(a, b), do: extract_var_name(a) == extract_var_name(b)

  defp extract_var_name({:__block__, _, [val]}), do: extract_var_name(val)
  defp extract_var_name({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: name
  defp extract_var_name(_), do: nil

  defp unwrap_literal({:__block__, _, [val]}), do: val
  defp unwrap_literal(val), do: val

  defp build_map_update(map, key, default, increment) do
    {{:., [], [{:__aliases__, [], [:Map]}, :update]}, [],
     [map, key | update_args(default, increment)]}
  end

  # Piped form: Map.update(k, default, fn x -> x + n end) — no map arg
  defp build_map_update_call(key, default, increment) do
    {{:., [], [{:__aliases__, [], [:Map]}, :update]}, [],
     [key | update_args(default, increment)]}
  end

  defp update_args(_default, 1) do
    increment_fn = {:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, 1]}]}]}
    [1, increment_fn]
  end

  defp update_args(_default, increment) when is_integer(increment) do
    increment_fn =
      {:fn, [], [{:->, [], [[{:x, [], nil}], {:+, [], [{:x, [], nil}, increment]}]}]}
    [increment, increment_fn]
  end

  defp update_args(default, increment) do
    # Fallback: non-literal increment
    [default, increment]
  end

  defp meta_of({{:., meta, _}, _, _}), do: meta
  defp meta_of(_), do: []

  defp build_issue(meta) do
    %Issue{
      rule: :no_map_put_get_increment,
      message:
        "`Map.put(m, k, Map.get(m, k, 0) + 1)` is a manual increment. " <>
          "Use `Map.update(m, k, 1, &(&1 + 1))` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
