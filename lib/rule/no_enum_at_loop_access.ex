defmodule Credence.Rule.NoEnumAtLoopAccess do
  @moduledoc """
  Performance heuristic rule: warns when `Enum.at/2` is used inside loops.

  Lists in Elixir are linked lists, so `Enum.at/2` is O(n).
  When used inside loops like `for`, `Enum.map`, or `Enum.reduce`,
  repeated indexing can lead to O(n²)-like behavior.

  This rule is a heuristic warning, not a strict error:
  small lists or one-off usage may be acceptable.

  Prefer:
    - converting to tuples for repeated indexing
    - or using Enum.with_index / direct iteration
  """

  use Credence.Rule
  alias Credence.Issue

  # Special forms/macros that act as loops
  @loop_macros [:for, :while]
  # Enum functions that act as loops
  @loop_enums [:map, :reduce, :each, :any?, :all?, :filter, :find, :flat_map]

  @impl true
  def check(ast, _opts) do
    # We use a depth counter instead of a boolean to handle nested loops
    {_ast, {issues, _depth}} =
      Macro.traverse(ast, {[], 0}, &pre_walker/2, &post_walker/2)

    Enum.reverse(issues)
  end

  # 1. Detect entering a 'for' loop
  defp pre_walker({loop, _, _} = node, {issues, depth}) when loop in @loop_macros do
    {node, {issues, depth + 1}}
  end

  # 2. Detect entering an 'Enum.xxx' loop
  defp pre_walker({{:., _, [{:__aliases__, _, [:Enum]}, loop]}, _, _} = node, {issues, depth})
       when loop in @loop_enums do
    {node, {issues, depth + 1}}
  end

  # 3. Detect Enum.at/2 only if depth > 0
  defp pre_walker(
         {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_list, index]} = node,
         {issues, depth}
       )
       when depth > 0 do
    if dynamic_index?(index) do
      {node, {[trigger_issue(meta) | issues], depth}}
    else
      {node, {issues, depth}}
    end
  end

  defp pre_walker(node, acc), do: {node, acc}

  # When leaving a node, if it was a loop, decrement the depth
  defp post_walker({loop, _, _} = node, {issues, depth}) when loop in @loop_macros do
    {node, {issues, depth - 1}}
  end

  defp post_walker({{:., _, [{:__aliases__, _, [:Enum]}, loop]}, _, _} = node, {issues, depth})
       when loop in @loop_enums do
    {node, {issues, depth - 1}}
  end

  defp post_walker(node, acc), do: {node, acc}

  defp dynamic_index?(index) do
    case index do
      idx when is_integer(idx) -> false
      _ -> true
    end
  end

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_enum_at_loop_access,
      message: """
      `Enum.at/2` inside a loop may cause O(n²) behavior on lists.

      Lists are linked structures, so each access is O(n).
      When used repeatedly in loops, this can become inefficient.

      Consider alternatives:
        - convert list to tuple once: List.to_tuple(list)
        - iterate directly: Enum.with_index / Enum.map
        - restructure data access pattern
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
