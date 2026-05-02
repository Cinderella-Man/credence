defmodule Credence.Rule.NoLengthInGuard do
  @moduledoc """
  Performance rule: Detects the use of `length/1` inside guard clauses (`when`).

  `length/1` traverses the entire list to compute its size, making it O(n).
  When placed in a guard, this cost is paid on every function call attempt,
  and the list is almost always traversed again inside the function body.

  ## Bad

      def process(list) when length(list) > 0 do
        Enum.map(list, &(&1 * 2))
      end

      def kth_largest(nums, k) when k <= length(nums) do
        Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end

  ## Good

      def process([_ | _] = list) do
        Enum.map(list, &(&1 * 2))
      end

      def kth_largest(nums, k) do
        if k > length(nums), do: raise(ArgumentError, "k out of bounds")
        Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end

  For non-empty checks, pattern matching (`[_ | _]`) is O(1) and idiomatic.
  For bounds checks, moving the validation into the function body avoids
  redundant traversals when the guard fails and another clause is tried.
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:def, meta, [{:when, _, [_call, guard]} | _rest]} = node, issues ->
          {node, find_length_in_guard(guard, meta, issues)}

        {:defp, meta, [{:when, _, [_call, guard]} | _rest]} = node, issues ->
          {node, find_length_in_guard(guard, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp find_length_in_guard(guard_ast, def_meta, acc) do
    {_ast, issues} =
      Macro.prewalk(guard_ast, acc, fn
        {:length, meta, [_arg]} = node, issues ->
          line = Keyword.get(meta, :line) || Keyword.get(def_meta, :line)

          issue = %Issue{
            rule: :no_length_in_guard,
            message:
              "Avoid `length/1` in guard clauses — it traverses the entire list (O(n)) on every call. " <>
                "Use pattern matching like `[_ | _]` for non-empty checks, or move the length check into the function body.",
            meta: %{line: line}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    issues
  end
end
