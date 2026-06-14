defmodule Credence.Pattern.NoExplicitSumReduceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoExplicitSumReduce

  describe "fix" do
    test "replaces sum reduce with Enum.sum/1" do
      input = "Enum.reduce(list, 0, fn x, acc -> acc + x end)"

      expected = "Enum.sum(list)"

      confirm_fix(fix(NoExplicitSumReduce, input), expected)
    end

    test "handles reversed operand order" do
      input = "Enum.reduce(list, 0, fn x, acc -> x + acc end)"

      expected = "Enum.sum(list)"

      confirm_fix(fix(NoExplicitSumReduce, input), expected)
    end

    test "does not modify non-sum reductions" do
      code = "Enum.reduce(list, 1, fn x, acc -> x * acc end)"

      confirm_fix(fix(NoExplicitSumReduce, code), code)
    end

    test "preserves surrounding code" do
      input = """
      defmodule M do
        def total(list) do
          count = length(list)
          sum = Enum.reduce(list, 0, fn x, acc -> acc + x end)
          {count, sum}
        end
      end
      """

      expected = """
      defmodule M do
        def total(list) do
          count = length(list)
          sum = Enum.sum(list)
          {count, sum}
        end
      end
      """

      confirm_fix(fix(NoExplicitSumReduce, input), expected)
    end

    test "round-trip: fixed code produces no issues" do
      code = "Enum.reduce(list, 0, fn x, acc -> x + acc end)"

      assert check(NoExplicitSumReduce, fix(NoExplicitSumReduce, code)) == []
    end
  end
end
