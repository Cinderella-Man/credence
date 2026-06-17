defmodule Credence.Pattern.PreferTupleDestructureAfterWithIndexFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferTupleDestructureAfterWithIndex

  test "rewrites the anti-pattern" do
    input = """
    matrix
    |> Enum.with_index()
    |> Enum.map(fn row, index ->
      {index, Enum.count(row, &(&1 == 1))}
    end)
    """

    expected = """
    matrix
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      {index, Enum.count(row, &(&1 == 1))}
    end)
    """

    confirm_fix(fix(PreferTupleDestructureAfterWithIndex, input), expected)
  end

  test "rewrites with longer pipe chain" do
    input = """
    list
    |> Enum.filter(&valid?/1)
    |> Enum.with_index()
    |> Enum.map(fn item, idx ->
      {idx, process(item)}
    end)
    """

    expected = """
    list
    |> Enum.filter(&valid?/1)
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      {idx, process(item)}
    end)
    """

    confirm_fix(fix(PreferTupleDestructureAfterWithIndex, input), expected)
  end

  test "does not rewrite single-arity fn with tuple destructure" do
    input = """
    matrix
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      {index, Enum.count(row, &(&1 == 1))}
    end)
    """

    confirm_fix(fix(PreferTupleDestructureAfterWithIndex, input), input)
  end

  test "does not rewrite Enum.map without preceding with_index" do
    input = """
    list
    |> Enum.map(fn x, y -> x + y end)
    """

    confirm_fix(fix(PreferTupleDestructureAfterWithIndex, input), input)
  end
end
