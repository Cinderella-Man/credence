defmodule Credence.Pattern.NoExplicitProductReduceCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoExplicitProductReduce

  describe "flags explicit product reductions" do
    test "detects x * acc pattern inside reduce" do
      code = """
      defmodule BadMultiply do
        def prod_value(list) do
          Enum.reduce(list, 1, fn x, acc ->
            x * acc
          end)
        end
      end
      """

      issues = check(NoExplicitProductReduce, code)
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

      issues = check(NoExplicitProductReduce, code)
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

      issues = check(NoExplicitProductReduce, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_product_reduce
    end

    test "detects bare Enum.reduce without alias prefix" do
      code = "Enum.reduce(list, 1, fn x, acc -> x * acc end)"

      assert length(check(NoExplicitProductReduce, code)) == 1
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

      assert length(check(NoExplicitProductReduce, code)) == 2
    end
  end

  describe "does not flag" do
    test "code that already uses Enum.product/1" do
      code = """
      defmodule GoodProduct do
        def prod_value(list) do
          Enum.product(list)
        end
      end
      """

      assert check(NoExplicitProductReduce, code) == []
    end

    test "sum reductions" do
      code = """
      defmodule GoodSum do
        def sum_value(list) do
          Enum.reduce(list, 0, fn x, acc -> x + acc end)
        end
      end
      """

      assert check(NoExplicitProductReduce, code) == []
    end

    test "reduce with non-1 initial accumulator" do
      code = """
      defmodule GoodNonOneAcc do
        def scaled_product(list) do
          Enum.reduce(list, 2, fn x, acc -> x * acc end)
        end
      end
      """

      assert check(NoExplicitProductReduce, code) == []
    end

    test "reduce with float 1.0 accumulator (would change result type)" do
      code = "Enum.reduce(list, 1.0, fn x, acc -> x * acc end)"

      assert check(NoExplicitProductReduce, code) == []
    end

    test "map-based reductions" do
      code = """
      defmodule GoodMapReduce do
        def build_map(list) do
          Enum.reduce(list, %{}, fn x, acc -> Map.put(acc, x, true) end)
        end
      end
      """

      assert check(NoExplicitProductReduce, code) == []
    end

    test "multiplication outside reduce" do
      code = """
      defmodule NoReduce do
        def multiply(a, b) do
          a * b
        end
      end
      """

      assert check(NoExplicitProductReduce, code) == []
    end

    test "product of something other than the two reducer params" do
      code = "Enum.reduce(list, 1, fn x, acc -> x * x end)"

      assert check(NoExplicitProductReduce, code) == []
    end

    test "multiplication by a literal, not the accumulator" do
      code = "Enum.reduce(list, 1, fn x, acc -> x * 2 end)"

      assert check(NoExplicitProductReduce, code) == []
    end

    # Narrowed-away unsafe case: `x()` is a zero-arity CALL to a function named
    # `x`, not the reducer parameter `x`. Rewriting to Enum.product would drop
    # that call and change the result, so we must not flag it.
    test "no issue: operand is a call that shares a param's name" do
      code = "Enum.reduce(list, 1, fn x, acc -> x() * acc end)"

      assert check(NoExplicitProductReduce, code) == []
    end

    # Narrowed-away unsafe case: a fn with two identically-named params requires
    # element == acc at every step (otherwise FunctionClauseError), which is not
    # what Enum.product/1 computes.
    test "no issue: reducer params share a name" do
      code = "Enum.reduce(list, 1, fn x, x -> x * x end)"

      assert check(NoExplicitProductReduce, code) == []
    end

    test "no issue: multi-statement reducer body" do
      code = """
      Enum.reduce(list, 1, fn x, acc ->
        y = x
        y * acc
      end)
      """

      assert check(NoExplicitProductReduce, code) == []
    end
  end
end
