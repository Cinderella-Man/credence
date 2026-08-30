defmodule Credence.Pattern.NoExplicitProductReduceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoExplicitProductReduce

  describe "rewrites explicit product reductions to Enum.product/1" do
    test "x * acc form" do
      code = "Enum.reduce(list, 1, fn x, acc -> x * acc end)"

      expected = "Enum.product(list)"

      confirm_fix(fix(NoExplicitProductReduce, code), expected)
    end

    test "acc * x form (reversed operand order)" do
      code = "Enum.reduce(list, 1, fn x, acc -> acc * x end)"

      expected = "Enum.product(list)"

      confirm_fix(fix(NoExplicitProductReduce, code), expected)
    end

    test "&*/2 capture form" do
      code = "Enum.reduce(list, 1, &*/2)"

      expected = "Enum.product(list)"

      confirm_fix(fix(NoExplicitProductReduce, code), expected)
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

      confirm_fix(fix(NoExplicitProductReduce, code), expected)
    end

    test "round-trip: fixed code produces no issues" do
      code = "Enum.reduce(list, 1, fn x, acc -> x * acc end)"

      fixed = fix(NoExplicitProductReduce, code)
      assert clean?(NoExplicitProductReduce, fixed)
    end
  end

  describe "leaves non-product code unchanged" do
    test "sum reduction" do
      code = "Enum.reduce(list, 0, fn x, acc -> x + acc end)"

      confirm_fix(fix(NoExplicitProductReduce, code), code)
    end

    test "non-1 accumulator" do
      code = "Enum.reduce(list, 2, fn x, acc -> x * acc end)"

      confirm_fix(fix(NoExplicitProductReduce, code), code)
    end

    test "operand is a call sharing a param's name" do
      code = "Enum.reduce(list, 1, fn x, acc -> x() * acc end)"

      confirm_fix(fix(NoExplicitProductReduce, code), code)
    end

    test "Enum is an alias for a custom module" do
      code = """
      defmodule AliasReduceProduct do
        alias MyEnum, as: Enum
        def product(list), do: Enum.reduce(list, 1, &*/2)
      end
      """

      confirm_fix(fix(NoExplicitProductReduce, code), code)
    end
  end
end
