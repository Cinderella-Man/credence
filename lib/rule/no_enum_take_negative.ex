defmodule Credence.Rule.NoEnumTakeNegative do
  @moduledoc """
  Performance rule: Detects `Enum.take(list, -n)` where `n` is a positive
  integer literal.

  For linked lists, `Enum.take(list, -n)` must internally determine the list
  length, then traverse again to the cut point — effectively two full
  traversals. If the list was just sorted, sorting in the opposite direction
  and taking a positive count is more efficient.

  ## Bad

      sorted = Enum.sort(nums)
      top_three = Enum.take(sorted, -3)

  ## Good

      top_three = Enum.sort(nums, :desc) |> Enum.take(3)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.take(list, -3)
        {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, meta, [_, {:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        # Piped: list |> Enum.take(-3)  — the negative is the only explicit arg
        {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, meta, [{:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(n, meta) do
    %Issue{
      rule: :no_enum_take_negative,
      message:
        "`Enum.take(list, -#{n})` forces a double traversal of the list to take from the end. " <>
          "Sort in the opposite direction and use `Enum.take(list, #{n})` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
