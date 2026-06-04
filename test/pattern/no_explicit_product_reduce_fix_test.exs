defmodule Credence.Pattern.NoExplicitProductReduceFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoExplicitProductReduce

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoExplicitProductReduce, code, [])

  describe "rewrites explicit product reductions to Enum.product/1" do
    test "x * acc form" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> x * acc end)
      """

      expected = """
      Enum.product(list)
      """

      assert fix(code) == expected
    end

    test "acc * x form (reversed operand order)" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> acc * x end)
      """

      expected = """
      Enum.product(list)
      """

      assert fix(code) == expected
    end

    test "&*/2 capture form" do
      code = """
      Enum.reduce(list, 1, &*/2)
      """

      expected = """
      Enum.product(list)
      """

      assert fix(code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def total(list) do
          count = length(list)
          product = Enum.reduce(list, 1, fn x, acc -> acc * x end)
          {count, product}
        end
      end
      """

      expected = """
      defmodule M do
        def total(list) do
          count = length(list)
          product = Enum.product(list)
          {count, product}
        end
      end
      """

      assert fix(code) == expected
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> x * acc end)
      """

      fixed = fix(code)
      assert NoExplicitProductReduce.check(Sourceror.parse_string!(fixed), []) == []
    end
  end

  describe "leaves non-product code unchanged" do
    test "sum reduction" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> x + acc end)
      """

      assert fix(code) == code
    end

    test "non-1 accumulator" do
      code = """
      Enum.reduce(list, 2, fn x, acc -> x * acc end)
      """

      assert fix(code) == code
    end

    test "operand is a call sharing a param's name" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> x() * acc end)
      """

      assert fix(code) == code
    end
  end
end
