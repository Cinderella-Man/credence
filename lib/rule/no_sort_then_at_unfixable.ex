defmodule Credence.Rule.NoSortThenAtUnfixable do
  @moduledoc """
  Performance rule (flag-only companion): Detects `Enum.sort |> Enum.at(index)`
  patterns where the index is **not** a compile-time literal `0` or `-1`, or the
  sort direction cannot be statically determined.

  These cases require human or LLM judgement to rewrite because the correct
  replacement depends on the runtime value of the index and/or sort direction.

  ## Examples that trigger this rule

      Enum.sort(nums, :desc) |> Enum.at(k - 1)       # variable index
      Enum.at(Enum.sort(nums), mid)                   # variable index
      Enum.sort(nums, dir) |> Enum.at(0)              # variable direction
      Enum.sort(nums, fn a, b -> a > b end) |> Enum.at(0)  # custom comparator

  ## What to do

  For index 0 → `Enum.min/1` or `Enum.max/1`.
  For index -1 → `Enum.max/1` or `Enum.min/1` (reversed).
  For other indices → `Enum.take/2` on the sorted list, or a partial-sort /
  quickselect algorithm.
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :at) and remote_call?(rightmost(left), :Enum, :sort) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

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
