defmodule Credence.Pattern.NoReduceForPartition do
  @moduledoc """
  Detects `Enum.reduce/3` used to partition a list into two groups, which
  can be replaced with `Enum.split_with/2`.

  ## Why this matters

  LLMs frequently implement list partitioning by manually accumulating
  into a `{[], []}` tuple with cons-prepend, then reversing both lists
  at the end.  A variant uses `{[], 0}` — collecting into one list and
  counting the other side — then reconstructing with `List.duplicate/2`.
  Both are textbook reimplementations of `Enum.split_with/2`:

      # Variant 1 — two lists
      {evens, odds} =
        Enum.reduce(list, {[], []}, fn
          x, {evens, odds} when rem(x, 2) == 0 -> {[x | evens], odds}
          x, {evens, odds} -> {evens, [x | odds]}
        end)
      {Enum.reverse(evens), Enum.reverse(odds)}

      # Variant 2 — list + counter
      {non_zeros, zero_count} =
        Enum.reduce(list, {[], 0}, fn
          0, {non_zeros, count} -> {non_zeros, count + 1}
          x, {non_zeros, count} -> {[x | non_zeros], count}
        end)
      Enum.reverse(non_zeros) ++ List.duplicate(0, zero_count)

      # Idiomatic — single function call
      {evens, odds} = Enum.split_with(list, &(rem(&1, 2) == 0))

  ## Flagged patterns

  - `Enum.reduce(enum, {[], []}, fn ...)` with two clauses, each
    returning a 2-tuple with one cons-prepend side and one bare variable.
  - `Enum.reduce(enum, {[], 0}, fn ...)` (or `{0, []}`) with two clauses:
    one cons-prepend + bare variable, the other bare variable + counter
    increment (`count + 1`).

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
    cond do
      empty_tuple_of_lists?(raw_acc) and partition_clauses?(clauses) ->
        {:ok, partition_issue(meta)}

      counting_accumulator?(raw_acc) and counting_partition_clauses?(clauses) ->
        {:ok, partition_issue(meta)}

      true ->
        :error
    end
  end

  defp partition_issue(meta) do
    %Issue{
      rule: :no_reduce_for_partition,
      message:
        "`Enum.reduce/3` manually partitions a list. " <>
          "Use `Enum.split_with/2` instead for a single pass " <>
          "with no manual reverse.",
      meta: %{line: Keyword.get(meta, :line)}
    }
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

  # Check if a node is the `{[], 0}` or `{0, []}` pattern (list + counter accumulator).
  defp counting_accumulator?(node) do
    case unwrap_block(node) do
      {raw_left, raw_right} ->
        left = unwrap_block(raw_left)
        right = unwrap_block(raw_right)
        (left == [] and right == 0) or (left == 0 and right == [])

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

  # Exactly two clauses: one with cons-prepend + bare var, other with bare var + counter increment.
  defp counting_partition_clauses?([
         {:->, _, [_patterns1, body1]},
         {:->, _, [_patterns2, body2]}
       ]) do
    s1 = clause_sides(body1)
    s2 = clause_sides(body2)

    (s1 == {:cons, :var} and s2 == {:var, :arithmetic}) or
      (s1 == {:var, :cons} and s2 == {:arithmetic, :var}) or
      (s1 == {:var, :arithmetic} and s2 == {:cons, :var}) or
      (s1 == {:arithmetic, :var} and s2 == {:var, :cons})
  end

  defp counting_partition_clauses?(_), do: false

  defp clause_sides(raw_body) do
    case unwrap_block(raw_body) do
      {raw_left, raw_right} ->
        {classify_tuple_side(raw_left), classify_tuple_side(raw_right)}

      _ ->
        {:other, :other}
    end
  end

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

      # count + 1 or 1 + count (integer may be __block__-wrapped in Sourceror)
      {:+, _, [left_node, right_node]} ->
        left = unwrap_block(left_node)
        right = unwrap_block(right_node)

        case {left, right} do
          {{name, _, ctx}, 1} when is_atom(name) and is_atom(ctx) -> :arithmetic
          {1, {name, _, ctx}} when is_atom(name) and is_atom(ctx) -> :arithmetic
          _ -> :other
        end

      _ ->
        :other
    end
  end

  # Strip Sourceror's __block__ wrappers to get to the actual value.
  defp unwrap_block({:__block__, _, [inner]}), do: unwrap_block(inner)
  defp unwrap_block(other), do: other
end
