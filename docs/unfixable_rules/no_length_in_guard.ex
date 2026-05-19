defmodule Credence.Pattern.NoLengthInGuard do
  @moduledoc """
  Performance rule: Detects the use of `length/1` inside guard clauses (`when`)
  in cases that cannot be automatically rewritten as pattern matches.

  `length/1` traverses the entire list to compute its size, making it O(n).
  When placed in a guard, this cost is paid on every function call attempt,
  and the list is almost always traversed again inside the function body.

  Note: simple non-empty checks (`length(list) > 0`) and exact-size checks
  (`length(list) == N` for N in 1..5) are handled by the `LengthGuardToPattern`
  rule, which can auto-fix them into pattern matches.

  ## Bad

      def kth_largest(nums, k) when k <= length(nums) do
        Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end

  ## Good

      def kth_largest(nums, k) do
        if k > length(nums), do: raise(ArgumentError, "k out of bounds")
        Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end

  For bounds checks, moving the validation into the function body avoids
  redundant traversals when the guard fails and another clause is tried.
  """
  use Credence.Pattern.Rule
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
        # Skip fixable pattern: length(var) > 0
        # Handled by LengthGuardToPattern rule.
        # Returning {nil, issues} prevents prewalk from visiting the
        # inner length call, so it won't be flagged here.
        {:>, _, [{:length, _, [_]}, 0]} = _node, issues ->
          {nil, issues}

        # Skip fixable pattern: length(var) == N where N in 1..5
        # Handled by LengthGuardToPattern rule.
        {:==, _, [{:length, _, [_]}, n]} = _node, issues
        when is_integer(n) and n >= 1 and n <= 5 ->
          {nil, issues}

        # Flag all other length/1 calls in guards
        {:length, meta, [_arg]} = node, issues ->
          line = Keyword.get(meta, :line) || Keyword.get(def_meta, :line)

          issue = %Issue{
            rule: :no_length_in_guard,
            message:
              "Avoid `length/1` in guard clauses — it traverses the entire list (O(n)) on every call. " <>
                "Move the length check into the function body to avoid redundant traversals.",
            meta: %{line: line}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    issues
  end
end
