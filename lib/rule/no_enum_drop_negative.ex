defmodule Credence.Rule.NoEnumDropNegative do
  @moduledoc """
  Performance rule: Detects `Enum.drop(list, -n)` where `n` is a positive
  integer literal.

  For linked lists, `Enum.drop(list, -n)` must traverse to the end of the
  list to figure out where to cut, making it O(n). This often indicates
  the algorithm should be restructured to avoid needing to trim from the
  tail of a linked list.

  ## Bad

      list |> Enum.drop(-1)

  ## Good

      # If building the list yourself, drop the head before reversing:
      [_ | rest] = reversed_list
      Enum.reverse(rest)

      # Or use Enum.slice/2 if you know the desired length:
      Enum.slice(list, 0..-2//1)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.drop(list, -1)
        {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, meta, [_, {:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        # Piped: list |> Enum.drop(-1)
        {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, meta, [{:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(n, meta) do
    %Issue{
      rule: :no_enum_drop_negative,
      message:
        "`Enum.drop(list, -#{n})` traverses the entire list to drop from the end. " <>
          "Restructure the algorithm to avoid tail-trimming on linked lists, " <>
          "or drop from the head of a reversed list instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
