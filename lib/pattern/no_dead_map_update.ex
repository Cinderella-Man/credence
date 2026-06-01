defmodule Credence.Pattern.NoDeadMapUpdate do
  @moduledoc """
  Detects `Map.update(key, ...) |> Map.drop([key])` and similar patterns
  where a `Map.update` result is immediately discarded by `Map.drop` or
  `Map.delete` on the same key.

  The `Map.update` call is dead code — its computed value is thrown away
  because the key is removed from the map in the very next step.

  ## Bad

      map |> Map.update(prev, 0, &(&1 - count)) |> Map.drop([prev])
      Map.delete(Map.update(map, key, default, fun), key)

  ## Good

      Map.drop(map, [prev])
      Map.delete(map, key)

  ## Auto-fix

  Removes the dead `Map.update` call, keeping only the drop/delete.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case match_dead_update(node) do
          {:ok, meta} -> {node, [build_issue(meta) | acc]}
          :no_match -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case match_dead_update(node) do
        {:ok, _meta} -> simplify(node)
        :no_match -> node
      end
    end)
  end

  # Piped form: map |> Map.update(key, ...) |> Map.drop([key_list])
  defp match_dead_update(
         {:|>, meta,
          [
            {:|>, _, [_map, update_call]},
            {{:., _, [{:__aliases__, _, [:Map]}, :drop]}, _, [drop_keys]}
          ]}
       ) do
    case update_call do
      {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [key | _]} ->
        if key_in_drop_list?(key, drop_keys) do
          {:ok, meta}
        else
          :no_match
        end

      _ ->
        :no_match
    end
  end

  # Piped form: map |> Map.update(key, ...) |> Map.delete(key)
  defp match_dead_update(
         {:|>, meta,
          [
            {:|>, _, [_map, update_call]},
            {{:., _, [{:__aliases__, _, [:Map]}, :delete]}, _, [del_key]}
          ]}
       ) do
    case update_call do
      {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [key | _]} ->
        if keys_match?(key, del_key) do
          {:ok, meta}
        else
          :no_match
        end

      _ ->
        :no_match
    end
  end

  # Direct form: Map.drop(Map.update(map, key, ...), [key_list])
  defp match_dead_update(
         {{:., meta, [{:__aliases__, _, [:Map]}, :drop]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [_map, key | _]},
            drop_keys
          ]}
       ) do
    if key_in_drop_list?(key, drop_keys) do
      {:ok, meta}
    else
      :no_match
    end
  end

  # Direct form: Map.delete(Map.update(map, key, ...), key)
  defp match_dead_update(
         {{:., meta, [{:__aliases__, _, [:Map]}, :delete]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [_map, key | _]},
            del_key
          ]}
       ) do
    if keys_match?(key, del_key) do
      {:ok, meta}
    else
      :no_match
    end
  end

  defp match_dead_update(_), do: :no_match

  # Replace the dead-update node with just the drop/delete, removing the update.
  defp simplify(
         {:|>, _,
          [
            {:|>, _, [map, _update_call]},
            {{:., _, [{:__aliases__, _, [:Map]}, :drop]}, _, [drop_keys]}
          ]}
       ) do
    # map |> Map.drop([key_list])
    {{:., [], [{:__aliases__, [], [:Map]}, :drop]}, [], [map, drop_keys]}
  end

  defp simplify(
         {:|>, _,
          [
            {:|>, _, [map, _update_call]},
            {{:., _, [{:__aliases__, _, [:Map]}, :delete]}, _, [del_key]}
          ]}
       ) do
    {{:., [], [{:__aliases__, [], [:Map]}, :delete]}, [], [map, del_key]}
  end

  defp simplify(
         {{:., _, [{:__aliases__, _, [:Map]}, :drop]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [map | _]},
            drop_keys
          ]}
       ) do
    {{:., [], [{:__aliases__, [], [:Map]}, :drop]}, [], [map, drop_keys]}
  end

  defp simplify(
         {{:., _, [{:__aliases__, _, [:Map]}, :delete]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [map | _]},
            del_key
          ]}
       ) do
    {{:., [], [{:__aliases__, [], [:Map]}, :delete]}, [], [map, del_key]}
  end

  defp simplify(node), do: node

  defp key_in_drop_list?(key, {:__block__, _, [list]}) when is_list(list) do
    Enum.any?(list, &keys_match?(key, &1))
  end

  defp key_in_drop_list?(key, list) when is_list(list) do
    Enum.any?(list, &keys_match?(key, &1))
  end

  defp key_in_drop_list?(_, _), do: false

  defp keys_match?({name, _, ctx}, {name, _, ctx2})
       when is_atom(name) and is_atom(ctx) and is_atom(ctx2),
       do: true

  defp keys_match?(literal, literal), do: true
  defp keys_match?(_, _), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_dead_map_update,
      message:
        "`Map.update(key, ...) |> Map.drop([key])` discards the update. " <>
          "Use `Map.drop(map, [key])` or `Map.delete(map, key)` directly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
