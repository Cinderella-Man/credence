defmodule Credence.Pattern.NoReverseThenFind do
  @moduledoc """
  Redundancy rule: Detects `Enum.reverse/1` immediately followed by `Enum.find/2,3`
  or `Enum.find_value/2,3` in a pipeline or nested call.

  `Enum.reverse |> Enum.find(pred)` is functionally "find the last element matching
  pred" — but it allocates an entire reversed intermediate list to search from the
  end. A single `Enum.reduce/3` (or `Enum.reduce_while/3`) avoids the allocation
  and scans the list once.

  ## Flagged patterns

      list |> Enum.reverse() |> Enum.find(&is_even/1)
      list |> Enum.reverse() |> Enum.find_value(0, fn x -> x * 2 end)
      Enum.find(Enum.reverse(list), &is_even/1)
      Enum.find_value(Enum.reverse(list), 0, fn x -> x * 2 end)

  ## Not flagged

      list |> Enum.reverse() |> Enum.map(...)   # different operation after reverse
      list |> Enum.reverse() |> Enum.sort(...)   # covered by no_reverse_then_sort
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @find_funcs [:find, :find_value]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline: ... |> Enum.reverse() |> Enum.find(...) / Enum.find_value(...)
        {:|>, meta, [left, right]} = node, issues ->
          reverse_node = rightmost(left)

          if find_call?(right) and remote_call?(reverse_node, :Enum, :reverse) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Nested: Enum.find(Enum.reverse(list), ...) / Enum.find_value(...)
        {{:., _, [{:__aliases__, _, [:Enum]}, func]}, meta, args} = node,
        issues
        when func in @find_funcs and is_list(args) and args != [] ->
          if remote_call?(hd(args), :Enum, :reverse) do
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
  def fix_patches(_ast, _opts), do: []

  defp find_call?(node) do
    match?({{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, _} when func in @find_funcs, node)
  end

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :no_reverse_then_find,
      message:
        "Avoid `Enum.reverse/1` before `Enum.find/2,3` or `Enum.find_value/2,3`. " <>
          "Use `Enum.reduce/3` to find the last matching element in a single pass " <>
          "without allocating an intermediate reversed list.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
