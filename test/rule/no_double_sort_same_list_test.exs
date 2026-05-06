defmodule Credence.Pattern.NoDoubleSortSameListTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoDoubleSortSameList.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoDoubleSortSameList.fix(code, [])
  end

  describe "NoDoubleSortSameList" do
    test "passes code that sorts once and reverses" do
      code = """
      defmodule GoodSort do
        def extremes(arr) do
          asc = Enum.sort(arr)
          desc = Enum.reverse(asc)
          {hd(asc), hd(desc)}
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that sorts a single direction" do
      code = """
      defmodule SingleSort do
        def process(arr) do
          Enum.sort(arr)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that sorts different lists" do
      code = """
      defmodule DifferentLists do
        def process(a, b) do
          sorted_a = Enum.sort(a)
          sorted_b = Enum.sort(b, :desc)
          {sorted_a, sorted_b}
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.sort(x) and Enum.sort(x, :desc) on same variable" do
      code = """
      defmodule BadDoubleSort do
        def max_product(arr) do
          asc = Enum.sort(arr)
          desc = Enum.sort(arr, :desc)
          [min1, min2 | _] = asc
          [max1, max2, max3 | _] = desc
          max(min1 * min2 * max1, max1 * max2 * max3)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_double_sort_same_list

      assert issue.message =~ "arr"
      assert issue.message =~ "sorted twice"
      assert issue.message =~ "Enum.reverse"
      assert issue.meta.line != nil
    end

    test "detects piped double sort on same variable" do
      code = """
      defmodule BadPiped do
        def process(arr) do
          asc = arr |> Enum.sort()
          desc = arr |> Enum.sort(:desc)
          {asc, desc}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_double_sort_same_list
    end

    test "detects the exact pattern from the real-world example" do
      code = """
      defmodule Solution do
        @spec maximum_product(list(integer())) :: integer()
        def maximum_product([_, _, _ | _] = arr) when is_list(arr) do
          asc = Enum.sort(arr)
          desc = Enum.sort(arr, :desc)

          [min1, min2 | _] = asc
          [max1, max2, max3 | _] = desc

          max(min1 * min2 * max1, max1 * max2 * max3)
        end

        def maximum_product(_), do: raise(ArgumentError, "need >= 3 elements")
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).message =~ "arr"
    end

    test "ignores sort with custom comparator functions" do
      code = """
      defmodule CustomSort do
        def process(items) do
          by_name = Enum.sort(items, &(&1.name <= &2.name))
          by_age = Enum.sort(items, &(&1.age <= &2.age))
          {by_name, by_age}
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fixable?" do
    test "reports as fixable" do
      assert Credence.Pattern.NoDoubleSortSameList.fixable?() == true
    end
  end

  describe "fix/2" do
    test "replaces desc sort with Enum.reverse of the asc binding" do
      code = """
      asc = Enum.sort(arr)
      desc = Enum.sort(arr, :desc)
      """

      result = fix(code)

      assert result =~ "Enum.sort(arr)"
      assert result =~ "Enum.reverse(asc)"
      refute result =~ "Enum.sort(arr, :desc)"
    end

    test "replaces piped desc sort with Enum.reverse" do
      code = """
      asc = arr |> Enum.sort()
      desc = arr |> Enum.sort(:desc)
      """

      result = fix(code)

      assert result =~ "Enum.reverse(asc)"
      refute result =~ "Enum.sort(:desc)"
    end

    test "does not modify code that sorts different lists" do
      code = """
      sorted_a = Enum.sort(a)
      sorted_b = Enum.sort(b, :desc)
      """

      result = fix(code)

      assert result =~ "Enum.sort(a)"
      assert result =~ "Enum.sort(b, :desc)"
    end

    test "does not modify code with custom comparator" do
      code = """
      by_name = Enum.sort(items, &(&1.name <= &2.name))
      by_age = Enum.sort(items, &(&1.age <= &2.age))
      """

      result = fix(code)

      refute result =~ "Enum.reverse"
    end

    test "fixes the real-world maximum_product example" do
      code = """
      defmodule Solution do
        def maximum_product(arr) do
          asc = Enum.sort(arr)
          desc = Enum.sort(arr, :desc)

          [min1, min2 | _] = asc
          [max1, max2, max3 | _] = desc

          max(min1 * min2 * max1, max1 * max2 * max3)
        end
      end
      """

      result = fix(code)

      assert result =~ "asc = Enum.sort(arr)"
      assert result =~ "Enum.reverse(asc)"
      refute result =~ "Enum.sort(arr, :desc)"
      # Surrounding code preserved
      assert result =~ "[min1, min2 | _] = asc"
      assert result =~ "[max1, max2, max3 | _] = desc"
    end

    test "preserves single-direction sorts" do
      code = """
      sorted = Enum.sort(list)
      """

      result = fix(code)

      assert result =~ "Enum.sort(list)"
      refute result =~ "Enum.reverse"
    end

    test "fixed code produces no issues" do
      code = """
      defmodule RoundTrip do
        def run(arr) do
          asc = Enum.sort(arr)
          desc = Enum.sort(arr, :desc)
          {asc, desc}
        end
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Code.string_to_quoted(fixed)
      issues = Credence.Pattern.NoDoubleSortSameList.check(fixed_ast, [])

      assert issues == []
    end
  end
end
