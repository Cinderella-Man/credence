defmodule Credence.Pattern.PreferTupleDestructureAfterWithIndexCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferTupleDestructureAfterWithIndex

  test "flags 2-arity fn after Enum.with_index in pipe" do
    assert flagged?(PreferTupleDestructureAfterWithIndex, """
           matrix
           |> Enum.with_index()
           |> Enum.map(fn row, index ->
             {index, Enum.count(row, &(&1 == 1))}
           end)
           """)
  end

  test "flags when with_index is earlier in a longer pipe" do
    assert flagged?(PreferTupleDestructureAfterWithIndex, """
           list
           |> Enum.filter(&valid?/1)
           |> Enum.with_index()
           |> Enum.map(fn item, idx ->
             {idx, process(item)}
           end)
           """)
  end

  test "leaves single-arity fn with tuple destructure alone" do
    assert clean?(PreferTupleDestructureAfterWithIndex, """
           matrix
           |> Enum.with_index()
           |> Enum.map(fn {row, index} ->
             {index, Enum.count(row, &(&1 == 1))}
           end)
           """)
  end

  test "leaves Enum.map without preceding with_index alone" do
    assert clean?(PreferTupleDestructureAfterWithIndex, """
           list
           |> Enum.map(fn x, y -> x + y end)
           """)
  end

  test "leaves Enum.map with 1-arity fn alone" do
    assert clean?(PreferTupleDestructureAfterWithIndex, """
           list
           |> Enum.with_index()
           |> Enum.map(fn {item, idx} -> transform(item, idx) end)
           """)
  end

  test "leaves code without pipes alone" do
    assert clean?(PreferTupleDestructureAfterWithIndex, "Enum.map(list, fn x -> x end)")
  end

  # Safe-core narrowing: the fix only knows how to wrap two *bare variables* in a
  # tuple (`fn a, b ->` => `fn {a, b} ->`). A 2-arity fn whose head contains a
  # non-variable pattern still crashes at runtime, but it is not this rule's safe
  # core — the fix would not produce the right destructuring — so we do not flag it.
  test "leaves 2-arity fn with a non-variable pattern argument alone" do
    assert clean?(PreferTupleDestructureAfterWithIndex, """
           matrix
           |> Enum.with_index()
           |> Enum.map(fn a, {b, c} ->
             {a, b, c}
           end)
           """)
  end

  test "leaves 2-arity fn with a destructured first argument alone" do
    assert clean?(PreferTupleDestructureAfterWithIndex, """
           matrix
           |> Enum.with_index()
           |> Enum.map(fn {a, b}, c ->
             {a, b, c}
           end)
           """)
  end

  test "leaves 2-arity fn with a literal pattern argument alone" do
    assert clean?(PreferTupleDestructureAfterWithIndex, """
           matrix
           |> Enum.with_index()
           |> Enum.map(fn a, 0 ->
             a
           end)
           """)
  end
end
