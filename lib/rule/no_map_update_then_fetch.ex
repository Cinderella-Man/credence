defmodule Credence.Rule.NoMapUpdateThenFetch do
  @moduledoc """
  Performance rule: Detects calling `Map.update/4` (or `Map.update!/3`) on a
  map variable and then immediately reading the same key back with
  `Map.fetch!/2` or `Map.get/2`.

  `Map.update/4` traverses the map to apply the new value. Following it with
  `Map.fetch!/2` or `Map.get/2` on the same variable performs a second
  independent traversal. Calculate the new value first, then use `Map.put/3`
  so both the value and the updated map are available without a second lookup.

  ## Bad

      map = Map.update(map, key, 1, &(&1 + 1))
      val = Map.fetch!(map, key)

  ## Good

      count = Map.get(map, key, 0) + 1
      map = Map.put(map, key, count)
      # `count` is already available — no second lookup needed
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    # Pass 1: collect variables bound to Map.update/Map.update!
    {_ast, update_vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{var, _, nil}, {{:., _, [{:__aliases__, _, [:Map]}, func]}, _, _}]} = node, acc
        when is_atom(var) and func in [:update, :update!] ->
          {node, MapSet.put(acc, var)}

        node, acc ->
          {node, acc}
      end)

    if MapSet.size(update_vars) == 0 do
      []
    else
      # Pass 2: find Map.fetch!/Map.get on any of those variables
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {{:., _, [{:__aliases__, _, [:Map]}, func]}, meta, [{var, _, nil} | _]} = node, acc
          when is_atom(var) and func in [:fetch!, :get] ->
            if MapSet.member?(update_vars, var) do
              {node, [build_issue(var, func, meta) | acc]}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  defp build_issue(var, fetch_func, meta) do
    %Issue{
      rule: :no_map_update_then_fetch,
      severity: :warning,
      message:
        "`Map.#{fetch_func}/2` is called on `#{var}` right after `Map.update/4`. " <>
          "This traverses the map twice. Compute the value first with `Map.get/3`, " <>
          "then use `Map.put/3` so both the value and updated map are available.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
