defmodule Credence.Rule.NoListLast do
  @moduledoc """
  Performance rule: Flags usage of `List.last/1`.

  Elixir lists are linked lists — accessing the last element requires
  traversing the entire list, making `List.last/1` an O(n) operation.
  This is often a sign that the algorithm should be restructured to
  build results in reverse (prepend + `Enum.reverse`) or use a different
  data structure.

  ## Bad

      {left, right} = Enum.split(combined, mid)
      (List.last(left) + List.first(right)) / 2

  ## Good

      # Use Enum.at/2 with a known index, or restructure:
      {left, [right_head | _]} = Enum.split(combined, mid)
      left_last = Enum.at(left, -1)
      (left_last + right_head) / 2

      # Even better — avoid needing the last element at all:
      Enum.at(combined, mid - 1)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match List.last(...)
        {{:., _, [{:__aliases__, _, [:List]}, :last]}, meta, _args} = node, issues ->
          issue = %Issue{
            rule: :no_list_last,
            severity: :warning,
            message:
              "`List.last/1` traverses the entire list (O(n)). Consider restructuring the algorithm " <>
                "to avoid needing the last element, or use `Enum.at(list, -1)` to make the cost explicit.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end
end
