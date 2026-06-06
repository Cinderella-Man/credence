defmodule Credence.Pattern.NoExplicitSumReduceFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoExplicitSumReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoExplicitSumReduce.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoExplicitSumReduce, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "replaces sum reduce with Enum.sum/1" do
      input = """
      Enum.reduce(list, 0, fn x, acc -> acc + x end)
      """

      expected = """
      Enum.sum(list)
      """

      assert fix(input) == expected
    end

    test "handles reversed operand order" do
      input = """
      Enum.reduce(list, 0, fn x, acc -> x + acc end)
      """

      expected = """
      Enum.sum(list)
      """

      assert fix(input) == expected
    end

    test "does not modify non-sum reductions" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> x * acc end)
      """

      assert fix(code) == code
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

      assert fix(input) == expected
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> x + acc end)
      """

      assert check(fix(code)) == []
    end
  end
end
