defmodule Credence.Pattern.NoExplicitProductReduceTest do
  use ExUnit.Case

  alias Credence.Pattern.NoExplicitProductReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoExplicitProductReduce.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoExplicitProductReduce, code, [])

  describe "NoExplicitProductReduce" do
    test "passes code that uses Enum.product/1 instead of reduce" do
      code = """
      defmodule GoodProduct do
        def prod_value(list) do
          Enum.product(list)
        end
      end
      """

      assert check(code) == []
    end

    test "detects if x * acc pattern inside reduce" do
      code = """
      defmodule BadMultiply do
        def prod_value(list) do
          Enum.reduce(list, 1, fn x, acc ->
            x * acc
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_product_reduce
    end

    test "detects &*/2 capture syntax" do
      code = """
      defmodule BadCapture do
        def prod_value(list) do
          Enum.reduce(list, 1, &*/2)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_product_reduce
    end

    test "detects acc * x pattern (reversed operand order)" do
      code = """
      defmodule BadMultiplyReversed do
        def prod_value(list) do
          Enum.reduce(list, 1, fn x, acc ->
            acc * x
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_product_reduce
    end

    test "does NOT detect sum reductions" do
      code = """
      defmodule GoodSum do
        def sum_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            x + acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect reduce with non-1 initial accumulator" do
      code = """
      defmodule GoodNonOneAcc do
        def scaled_product(list) do
          Enum.reduce(list, 2, fn x, acc ->
            x * acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect map-based reductions" do
      code = """
      defmodule GoodMapReduce do
        def build_map(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, true)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects multiple explicit product calls inside separate reduces" do
      code = """
      defmodule MultipleBadProduct do
        def process(a, b) do
          x = Enum.reduce(a, 1, fn v, acc -> v * acc end)
          y = Enum.reduce(b, 1, fn v, acc -> v * acc end)
          {x, y}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end

    test "ignores multiplication outside reduce" do
      code = """
      defmodule NoReduce do
        def multiply(a, b) do
          a * b
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces product reduce with Enum.product/1" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> acc * x end)
      """

      result = fix(code)
      assert result =~ "Enum.product(list)"
      refute result =~ "Enum.reduce"
    end

    test "replaces &*/2 capture with Enum.product/1" do
      code = """
      Enum.reduce(list, 1, &*/2)
      """

      result = fix(code)
      assert result =~ "Enum.product(list)"
      refute result =~ "Enum.reduce"
    end

    test "handles reversed operand order" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> x * acc end)
      """

      result = fix(code)
      assert result =~ "Enum.product(list)"
    end

    test "does not modify non-product reductions" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> x + acc end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      refute result =~ "Enum.product"
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

      result = fix(code)
      assert result =~ "length(list)"
      assert result =~ "Enum.product(list)"
      assert result =~ "{count, product}"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> x * acc end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoExplicitProductReduce.check(ast, []) == []
    end

    test "round-trip: &*/2 capture fix produces no issues" do
      code = """
      Enum.reduce(list, 1, &*/2)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoExplicitProductReduce.check(ast, []) == []
    end
  end
end
