defmodule Credence.Rule.NoSortThenAt do
  @moduledoc """
  Performance rule: Detects sorting an entire list only to retrieve a single
  element by index via `Enum.at/2`.

  Sorting is O(n log n), and if you only need one element (e.g. the kth
  largest or the median), the full sort is wasteful. For k=1 use `Enum.min/1`
  or `Enum.max/1` (O(n)). For small k, consider a partial sort or heap.

  ## Bad

      Enum.sort(nums, :desc) |> Enum.at(k - 1)
      Enum.at(Enum.sort(nums), 0)

  ## Good

      Enum.min(nums)                       # for the smallest
      Enum.max(nums)                       # for the largest
      Enum.sort(nums) |> Enum.take(k)      # when you need the top-k list
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline form: ... |> Enum.sort(...) |> Enum.at(...)
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :at) and remote_call?(rightmost(left), :Enum, :sort) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Nested call form: Enum.at(Enum.sort(...), index)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, _} | _rest
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_sort_then_at,
      message:
        "Sorting a list and then accessing a single element with `Enum.at/2` is O(n log n) " <>
          "when you may only need O(n). For min/max, use `Enum.min/1` or `Enum.max/1`. " <>
          "For top-k, consider `Enum.take/2` on the sorted result.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
