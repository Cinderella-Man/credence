defmodule Credence.Pattern.NoReduceForPartition do
  @moduledoc """
  Detects `Enum.reduce/3` with a `{[], []}` accumulator used to partition
  a list into two groups by prepending elements into one of two lists,
  which can be replaced with `Enum.split_with/2`.

  ## Why this matters

  LLMs frequently implement list partitioning by manually accumulating
  into a `{[], []}` tuple with cons-prepend, then reversing both lists
  at the end.  This is a textbook reimplementation of
  `Enum.split_with/2`, which does the same thing in a single pass with
  no manual reverse:

      # Flagged — manual reduce-based partition
      {evens, odds} =
        Enum.reduce(list, {[], []}, fn
          x, {evens, odds} when rem(x, 2) == 0 -> {[x | evens], odds}
          x, {evens, odds} -> {evens, [x | odds]}
        end)
      {Enum.reverse(evens), Enum.reverse(odds)}

      # Idiomatic — single function call
      {evens, odds} = Enum.split_with(list, &(rem(&1, 2) == 0))

  ## Flagged patterns

  `Enum.reduce(enum, {[], []}, fn ...)` where the anonymous function has
  exactly two clauses, each returning a 2-tuple with one side receiving
  a cons-prepend and the other side left unchanged.

  ## Not flagged

  - Reduces that transform elements while partitioning
  - Reduces with non-empty initial accumulators
  - Reduces with more or fewer than two clauses
  - Partitions into more than two groups
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Direct call: Enum.reduce(list, {[], []}, fn ...)
  defp check_node(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta,
          [_list, acc, {:fn, _, clauses}]}
       ) do
    check_reduce_partition(acc, clauses, meta)
  end

  # Piped call: ... |> Enum.reduce({[], []}, fn ...)
  defp check_node(
         {:|>, _,
          [
            _source,
            {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta,
             [acc, {:fn, _, clauses}]}
          ]}
       ) do
    check_reduce_partition(acc, clauses, meta)
  end

  defp check_node(_), do: :error

  defp check_reduce_partition(raw_acc, clauses, meta) do
    if empty_tuple_of_lists?(raw_acc) and partition_clauses?(clauses) do
      {:ok,
       %Issue{
         rule: :no_reduce_for_partition,
         message:
           "`Enum.reduce/3` with a `{[], []}` accumulator manually " <>
             "partitions a list. Use `Enum.split_with/2` instead for a single pass " <>
             "with no manual reverse.",
         meta: %{line: Keyword.get(meta, :line)}
       }}
    else
      :error
    end
  end

  # Check if a node is the `{[], []}` pattern, unwrapping __block__ wrappers.
  defp empty_tuple_of_lists?(node) do
    case unwrap_block(node) do
      {raw_left, raw_right} ->
        unwrap_block(raw_left) == [] and unwrap_block(raw_right) == []

      _ ->
        false
    end
  end

  # Exactly two clauses, each body is a 2-tuple with one cons-prepend side.
  defp partition_clauses?([
         {:->, _, [_patterns1, body1]},
         {:->, _, [_patterns2, body2]}
       ]) do
    cons_partition_tuple?(body1) and cons_partition_tuple?(body2)
  end

  defp partition_clauses?(_), do: false

  # A 2-tuple (wrapped in __block__) where exactly one side is [var | var]
  # and the other is a bare variable.
  defp cons_partition_tuple?(raw_body) do
    case unwrap_block(raw_body) do
      {raw_left, raw_right} ->
        left = classify_tuple_side(raw_left)
        right = classify_tuple_side(raw_right)
        (left == :cons and right == :var) or (left == :var and right == :cons)

      _ ->
        false
    end
  end

  # A cons cell: [elem | acc] where both are bare variables.
  # In Sourceror AST this is wrapped in __block__: {:__block__, _, [[{:|, _, [var, var]}]]}
  defp classify_tuple_side(raw_node) do
    case unwrap_block(raw_node) do
      [{:|, _, [{left_name, _, left_ctx}, {right_name, _, right_ctx}]}]
      when is_atom(left_name) and is_atom(left_ctx) and is_atom(right_name) and
             is_atom(right_ctx) ->
        :cons

      {name, _, ctx} when is_atom(name) and is_atom(ctx) ->
        :var

      _ ->
        :other
    end
  end

  # Strip Sourceror's __block__ wrappers to get to the actual value.
  defp unwrap_block({:__block__, _, [inner]}), do: unwrap_block(inner)
  defp unwrap_block(other), do: other
end
