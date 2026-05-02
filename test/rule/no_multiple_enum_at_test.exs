defmodule Credence.Rule.NoMultipleEnumAtTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoMultipleEnumAt.check(ast, [])
  end

  describe "NoMultipleEnumAt" do
    test "passes code that uses pattern matching" do
      code = """
      defmodule GoodCode do
        def extremes(nums) do
          sorted = Enum.sort(nums)
          [min1, min2 | _] = sorted
          [max1, max2 | _] = Enum.reverse(sorted)
          {min1, min2, max1, max2}
        end
      end
      """

      assert check(code) == []
    end

    test "passes code with only 1-2 Enum.at calls on the same var" do
      code = """
      defmodule FewCalls do
        def first_two(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          {a, b}
        end
      end
      """

      assert check(code) == []
    end

    test "detects 3+ Enum.at calls on the same variable" do
      code = """
      defmodule BadDestructure do
        def max_product(nums) do
          sorted = Enum.sort(nums)
          min1 = Enum.at(sorted, 0)
          min2 = Enum.at(sorted, 1)
          max1 = Enum.at(sorted, -1)
          max2 = Enum.at(sorted, -2)
          max(min1 * min2, max1 * max2)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_multiple_enum_at

      assert issue.message =~ "sorted"
      assert issue.message =~ "pattern matching"
      assert issue.meta.line != nil
    end

    test "ignores Enum.at with non-literal indices" do
      code = """
      defmodule DynamicIndex do
        def get_elements(list, indices) do
          Enum.map(indices, fn i -> Enum.at(list, i) end)
        end
      end
      """

      assert check(code) == []
    end

    test "flags each variable independently" do
      code = """
      defmodule TwoVars do
        def process(a, b) do
          x1 = Enum.at(a, 0)
          x2 = Enum.at(a, 1)
          x3 = Enum.at(a, 2)
          y1 = Enum.at(b, 0)
          {x1, x2, x3, y1}
        end
      end
      """

      issues = check(code)

      # Only `a` has 3+ calls, `b` has just 1
      assert length(issues) == 1
      assert hd(issues).message =~ "a"
    end
  end
end
