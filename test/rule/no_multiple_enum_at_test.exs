defmodule Credence.Pattern.NoMultipleEnumAtTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoMultipleEnumAt.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoMultipleEnumAt.fix(code, [])
  end

  describe "check" do
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
      assert length(issues) == 1
      assert hd(issues).message =~ "a"
    end

    test "detects negative literal indices" do
      code = """
      defmodule NegIndices do
        def tail(list) do
          a = Enum.at(list, -1)
          b = Enum.at(list, -2)
          c = Enum.at(list, -3)
          {a, b, c}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "list"
    end
  end

  describe "fix" do
    test "fixes contiguous sequential positive indices" do
      source = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          c = Enum.at(list, 2)
          {a, b, c}
        end
      end
      """

      fixed = fix(source)
      assert fixed =~ "[a, b, c | _] = list"
      refute fixed =~ "Enum.at(list"
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end

    test "fixes contiguous positive indices with small gaps" do
      source = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 2)
          c = Enum.at(list, 3)
          {a, b, c}
        end
      end
      """

      fixed = fix(source)
      assert fixed =~ "[a, _, b, c | _] = list"
      refute fixed =~ "Enum.at(list"
    end

    test "fixes contiguous negative indices" do
      source = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, -1)
          b = Enum.at(list, -2)
          c = Enum.at(list, -3)
          {a, b, c}
        end
      end
      """

      fixed = fix(source)
      assert fixed =~ "[a, b, c | _] = Enum.reverse(list)"
      refute fixed =~ "Enum.at(list"
    end

    test "fixes mixed positive and negative indices" do
      source = """
      defmodule Example do
        def run(sorted) do
          min1 = Enum.at(sorted, 0)
          min2 = Enum.at(sorted, 1)
          max1 = Enum.at(sorted, -1)
          max2 = Enum.at(sorted, -2)
          {min1, min2, max1, max2}
        end
      end
      """

      fixed = fix(source)
      assert fixed =~ "[min1, min2 | _] = sorted"
      assert fixed =~ "[max1, max2 | _] = Enum.reverse(sorted)"
      refute fixed =~ "Enum.at"
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end

    test "returns source unchanged when nothing to fix" do
      source = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          {a, b}
        end
      end
      """

      assert fix(source) == source
    end

    test "does not fix sparse indices" do
      source = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 100)
          c = Enum.at(list, 200)
          {a, b, c}
        end
      end
      """

      assert fix(source) == source
    end

    test "fixes contiguous subset when separated by other code" do
      source = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          IO.puts(a)
          b = Enum.at(list, 1)
          c = Enum.at(list, 2)
          d = Enum.at(list, 3)
          {a, b, c, d}
        end
      end
      """

      fixed = fix(source)
      assert fixed =~ "[_, b, c, d | _] = list"
      assert fixed =~ "Enum.at(list, 0)"
      assert fixed =~ "IO.puts(a)"
    end

    test "preserves surrounding code" do
      source = """
      defmodule Example do
        def run(list) do
          before = :ok
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          c = Enum.at(list, 2)
          after_val = :done
          {before, a, b, c, after_val}
        end
      end
      """

      fixed = fix(source)
      assert fixed =~ "before = :ok"
      assert fixed =~ "[a, b, c | _] = list"
      assert fixed =~ "after_val = :done"
      refute fixed =~ "Enum.at(list"
    end

    test "fixes the documentation example end-to-end" do
      source = """
      defmodule Example do
        def extremes(nums) do
          sorted = Enum.sort(nums)
          min1 = Enum.at(sorted, 0)
          min2 = Enum.at(sorted, 1)
          max1 = Enum.at(sorted, -1)
          max2 = Enum.at(sorted, -2)
          max(min1 * min2, max1 * max2)
        end
      end
      """

      fixed = fix(source)
      assert fixed =~ "[min1, min2 | _] = sorted"
      assert fixed =~ "[max1, max2 | _] = Enum.reverse(sorted)"
      assert fixed =~ "max(min1 * min2, max1 * max2)"
      refute fixed =~ "Enum.at"
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end

    test "fixed code has fewer check issues" do
      source = """
      defmodule Example do
        def run(sorted) do
          min1 = Enum.at(sorted, 0)
          min2 = Enum.at(sorted, 1)
          max1 = Enum.at(sorted, -1)
          max2 = Enum.at(sorted, -2)
          {min1, min2, max1, max2}
        end
      end
      """

      {:ok, ast_before} = Code.string_to_quoted(source)
      issues_before = Credence.Pattern.NoMultipleEnumAt.check(ast_before, [])
      assert length(issues_before) >= 1

      fixed = fix(source)
      {:ok, ast_after} = Code.string_to_quoted(fixed)
      issues_after = Credence.Pattern.NoMultipleEnumAt.check(ast_after, [])
      assert length(issues_after) < length(issues_before)
    end
  end
end
