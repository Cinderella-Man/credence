defmodule Credence.Pattern.NoReduceWhileWithoutHaltFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoReduceWhileWithoutHalt

  test "replaces reduce_while with reduce and unwraps {:cont, _}" do
    code = """
    Enum.reduce_while(list, 0, fn x, acc ->
      {:cont, acc + x}
    end)
    """

    expected = """
    Enum.reduce(list, 0, fn x, acc ->
      acc + x
    end)
    """

    assert fix(NoReduceWhileWithoutHalt, code) == expected
  end

  test "handles pipeline form with multi-line block body" do
    code = """
    list
    |> Enum.reduce_while({0, []}, fn h, {max, acc} ->
      new_max = max(h, max)
      {:cont, {new_max, [new_max | acc]}}
    end)
    """

    expected = """
    list
    |> Enum.reduce({0, []}, fn h, {max, acc} ->
      new_max = max(h, max)
      {new_max, [new_max | acc]}
    end)
    """

    assert fix(NoReduceWhileWithoutHalt, code) == expected
  end

  test "preserves surrounding code" do
    code = """
    defmodule M do
      def process(list) do
        count = length(list)
        sum = Enum.reduce_while(list, 0, fn x, acc -> {:cont, acc + x} end)
        {count, sum}
      end
    end
    """

    expected = """
    defmodule M do
      def process(list) do
        count = length(list)
        sum = Enum.reduce(list, 0, fn x, acc -> acc + x end)
        {count, sum}
      end
    end
    """

    assert fix(NoReduceWhileWithoutHalt, code) == expected
  end

  test "unwraps every clause of a multi-clause fn" do
    code = """
    Enum.reduce_while(list, 0, fn
      x, acc when x > 0 -> {:cont, acc + x}
      x, acc -> {:cont, acc - x}
    end)
    """

    expected = """
    Enum.reduce(list, 0, fn
      x, acc when x > 0 -> acc + x
      x, acc -> acc - x
    end)
    """

    assert fix(NoReduceWhileWithoutHalt, code) == expected
  end

  test "does not modify reduce_while with :halt" do
    code = """
    Enum.reduce_while(list, 0, fn x, acc ->
      if x < 0, do: {:halt, acc}, else: {:cont, acc + x}
    end)
    """

    assert fix(NoReduceWhileWithoutHalt, code) == code
  end

  test "does not modify a cont buried inside a case (not the literal last expr)" do
    code = """
    Enum.reduce_while(list, 0, fn x, acc ->
      case x do
        0 -> {:cont, acc}
        _ -> {:cont, acc + x}
      end
    end)
    """

    assert fix(NoReduceWhileWithoutHalt, code) == code
  end

  test "round-trip: fixed code produces no issues" do
    code = """
    Enum.reduce_while(list, 0, fn x, acc ->
      {:cont, acc + x}
    end)
    """

    fixed = fix(NoReduceWhileWithoutHalt, code)
    ast = Sourceror.parse_string!(fixed)
    assert NoReduceWhileWithoutHalt.check(ast, []) == []
  end
end
