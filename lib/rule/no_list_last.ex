defmodule Credence.Rule.NoListLast do
  @moduledoc """
  Performance rule: Flags usage of `List.last/1`.

  Elixir lists are linked lists — accessing the last element requires
  traversing the entire list, making `List.last/1` an O(n) operation.
  This is often a sign that the algorithm should be restructured to
  avoid needing the last element entirely.

  ## Common refactors

  - If building a list with `Enum.reduce`, track the last value in the
    accumulator instead of extracting it afterward
  - If splitting a list, destructure the right half instead of taking
    the last of the left half
  - If the list was sorted or built in a known order, consider whether
    `hd/1` on a reversed or desc-sorted list gives you the answer

  ## Bad

      Enum.reduce(1..(rows - 1), initial_row, fn _, prev ->
        Enum.scan(prev, &(&1 + &2))
      end)
      |> List.last()

  ## Good — track the answer in the accumulator

      {_row, last} =
        Enum.reduce(1..(rows - 1), {initial_row, 1}, fn _, {prev, _} ->
          row = Enum.scan(prev, &(&1 + &2))
          {row, List.last(row)}  # or track running total differently
        end)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:List]}, :last]}, meta, _args} = node, issues ->
          issue = %Issue{
            rule: :no_list_last,
            severity: :warning,
            message:
              "`List.last/1` traverses the entire list (O(n)). " <>
                "Restructure to avoid needing the last element: " <>
                "track the value in an accumulator, destructure from the other end, " <>
                "or reverse before taking the head. " <>
                "Do NOT reimplement List.last manually — that has the same O(n) cost.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end
end
