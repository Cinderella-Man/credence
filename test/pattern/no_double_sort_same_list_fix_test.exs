defmodule Credence.Pattern.NoDoubleSortSameListFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDoubleSortSameList

  describe "fix/2" do
    test "replaces desc sort with Enum.reverse of the asc binding" do
      input = """
      asc = Enum.sort(arr)
      desc = Enum.sort(arr, :desc)
      """

      expected = """
      asc = Enum.sort(arr)
      desc = Enum.reverse(asc)
      """

      assert fix(NoDoubleSortSameList, input) == expected
    end

    test "replaces piped desc sort with Enum.reverse" do
      input = """
      asc = arr |> Enum.sort()
      desc = arr |> Enum.sort(:desc)
      """

      expected = """
      asc = arr |> Enum.sort()
      desc = Enum.reverse(asc)
      """

      assert fix(NoDoubleSortSameList, input) == expected
    end

    test "does not modify code that sorts different lists" do
      code = """
      sorted_a = Enum.sort(a)
      sorted_b = Enum.sort(b, :desc)
      """

      assert fix(NoDoubleSortSameList, code) == code
    end

    test "does not modify code with custom comparator" do
      code = """
      by_name = Enum.sort(items, &(&1.name <= &2.name))
      by_age = Enum.sort(items, &(&1.age <= &2.age))
      """

      assert fix(NoDoubleSortSameList, code) == code
    end

    test "fixes the real-world maximum_product example" do
      input = """
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

      expected = """
      defmodule Solution do
        def maximum_product(arr) do
          asc = Enum.sort(arr)
          desc = Enum.reverse(asc)

          [min1, min2 | _] = asc
          [max1, max2, max3 | _] = desc

          max(min1 * min2 * max1, max1 * max2 * max3)
        end
      end
      """

      assert fix(NoDoubleSortSameList, input) == expected
    end

    test "preserves single-direction sorts" do
      code = """
      sorted = Enum.sort(list)
      """

      assert fix(NoDoubleSortSameList, code) == code
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

      assert check(NoDoubleSortSameList, fix(NoDoubleSortSameList, code)) == []
    end
  end
end
