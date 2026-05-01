defmodule Credence.Rule.NoMapKeysOrValuesForIteration do
  @moduledoc """
  Performance rule: Detects `Map.values(map)` or `Map.keys(map)` passed
  directly into an `Enum` function, which creates an unnecessary intermediate
  list.

  All `Enum` functions accept maps directly and iterate over `{key, value}`
  pairs without allocating an intermediate list.

  ## Bad

      Enum.all?(Map.values(degrees), fn v -> v == 0 end)
      Map.keys(map) |> Enum.map(&to_string/1)

  ## Good

      Enum.all?(degrees, fn {_k, v} -> v == 0 end)
      Enum.map(map, fn {k, _v} -> to_string(k) end)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @map_funcs [:keys, :values]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Nested: Enum.func(Map.keys/values(m), ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, meta,
         [{{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _} | _]} = node,
        issues
        when mfunc in @map_funcs ->
          {node, [build_issue(mfunc, efunc, meta) | issues]}

        # Piped: Map.keys/values(m) |> Enum.func(...)
        {:|>, meta,
         [
           {{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _},
           {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, _, _}
         ]} = node,
        issues
        when mfunc in @map_funcs ->
          {node, [build_issue(mfunc, efunc, meta) | issues]}

        # Piped from variable via intermediate pipe:
        # map |> Map.keys/values() |> Enum.func(...)
        {:|>, meta,
         [
           {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _}]},
           {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, _, _}
         ]} = node,
        issues
        when mfunc in @map_funcs ->
          {node, [build_issue(mfunc, efunc, meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(mfunc, efunc, meta) do
    %Issue{
      rule: :no_map_keys_or_values_for_iteration,
      severity: :info,
      message:
        "`Map.#{mfunc}/1` creates an intermediate list before passing to `Enum.#{efunc}/2`. " <>
          "Iterate the map directly — `Enum` functions accept maps and yield `{key, value}` pairs.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
