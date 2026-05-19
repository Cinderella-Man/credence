defmodule Credence.Pattern.NoMapAsSet do
  @moduledoc """
  Style rule: Detects using a `Map` with boolean literal values (`true`/`false`)
  purely for membership tracking, when `MapSet` is more appropriate.

  `Map.put(seen, item, true)` paired with `Map.has_key?(seen, item)` is a
  manual reimplementation of `MapSet.put/2` and `MapSet.member?/2`. Using
  `MapSet` makes the intent clearer and avoids storing meaningless values.

  This rule is **not auto-fixable** because a correct transformation requires
  companion changes beyond the flagged call site — initialising the variable
  with `MapSet.new()` instead of `%{}`, and replacing the corresponding
  `Map.has_key?/2` check with `MapSet.member?/2`.  Those changes involve
  data-flow analysis that cannot be done safely with a local AST rewrite.

  ## Bad

      # Boolean value used purely for membership tracking
      Map.put(seen, item, true)
      Map.put(seen, item, false)

      # Typical pattern this catches
      if Map.has_key?(seen, item) do
        {seen, acc}
      else
        {Map.put(seen, item, true), [item | acc]}
      end

  ## Good

      if MapSet.member?(seen, item) do
        {seen, acc}
      else
        {MapSet.put(seen, item), [item | acc]}
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Map.put(var, key, true/false) — direct call (3 args)
        {{:., _, [{:__aliases__, _, [:Map]}, :put]}, meta, [_, _, bool]} = node, issues
        when bool in [true, false] ->
          {node, [build_issue(meta, bool) | issues]}

        # map |> Map.put(key, true/false) — pipeline call (2 args, first is piped)
        {{:., _, [{:__aliases__, _, [:Map]}, :put]}, meta, [_, bool]} = node, issues
        when bool in [true, false] ->
          {node, [build_issue(meta, bool) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(meta, bool) do
    %Issue{
      rule: :no_map_as_set,
      message:
        "`Map.put/3` called with boolean literal `#{inspect(bool)}` — " <>
          "this suggests the map is used purely for membership tracking. " <>
          "Use `MapSet` instead: `MapSet.put/2` and `MapSet.member?/2` " <>
          "make the intent explicit.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
