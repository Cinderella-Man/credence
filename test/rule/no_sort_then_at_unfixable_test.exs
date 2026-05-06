defmodule Credence.Pattern.NoSortThenAtUnfixableTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoSortThenAtUnfixable.check(ast, [])
  end

  describe "check/2 – variable index (pipeline)" do
    test "flags Enum.sort |> Enum.at(k - 1)" do
      code = """
      defmodule M do
        def kth(nums, k), do: Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags Enum.sort |> Enum.at(k)" do
      code = """
      defmodule M do
        def nth(nums, k), do: Enum.sort(nums) |> Enum.at(k)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags longer pipeline with variable index" do
      code = """
      defmodule M do
        def top(nums, k) do
          nums
          |> Enum.sort(:desc)
          |> Enum.at(k - 1)
        end
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end
  end

  describe "check/2 – variable index (nested)" do
    test "flags Enum.at(Enum.sort(nums), mid)" do
      code = """
      defmodule M do
        def median(nums) do
          mid = div(length(nums), 2)
          Enum.at(Enum.sort(nums), mid)
        end
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end
  end

  describe "check/2 – variable direction" do
    test "flags Enum.sort(nums, dir) |> Enum.at(0)" do
      code = """
      defmodule M do
        def first(nums, dir), do: Enum.sort(nums, dir) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end
  end

  describe "check/2 – custom comparator" do
    test "flags Enum.sort with custom function |> Enum.at(0)" do
      code = """
      defmodule M do
        def first(nums), do: Enum.sort(nums, fn a, b -> a > b end) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end
  end

  describe "check/2 – negative cases" do
    test "does not flag Enum.min/Enum.max" do
      code = """
      defmodule M do
        def smallest(nums), do: Enum.min(nums)
        def largest(nums), do: Enum.max(nums)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.take" do
      code = """
      defmodule M do
        def top3(nums), do: Enum.sort(nums, :desc) |> Enum.take(3)
      end
      """

      assert check(code) == []
    end

    test "does not flag plain Enum.at" do
      code = """
      defmodule M do
        def get(list, i), do: Enum.at(list, i)
      end
      """

      assert check(code) == []
    end
  end
end
