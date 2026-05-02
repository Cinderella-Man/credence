defmodule Credence.Rule.NoMapAsSet do
  @moduledoc """
  Style rule: Detects using a `Map` with boolean literal values (`true`/`false`)
  purely for membership tracking, when `MapSet` is more appropriate.

  `Map.put(seen, item, true)` paired with `Map.has_key?(seen, item)` is a
  manual reimplementation of `MapSet.put/2` and `MapSet.member?/2`. Using
  `MapSet` makes the intent clearer and avoids storing meaningless values.

  ## Bad

      {Map.put(seen, item, true), [item | acc]}

  ## Good

      {MapSet.put(seen, item), [item | acc]}
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Map.put(var, key, true) or Map.put(var, key, false)
        {{:., _, [{:__aliases__, _, [:Map]}, :put]}, meta, [_, _, bool]} = node, issues
        when bool in [true, false] ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_map_as_set,
      message:
        "`Map.put/3` with a boolean literal value suggests the map is used purely for " <>
          "membership tracking. Use `MapSet` instead — `MapSet.put/2` and " <>
          "`MapSet.member?/2` make the intent explicit.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
