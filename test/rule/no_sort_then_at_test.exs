defmodule Credence.Rule.NoSortThenAtTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoSortThenAt.check(ast, [])
  end

  describe "NoSortThenAt" do
    test "passes code that uses Enum.min or Enum.max" do
      code = """
      defmodule GoodCode do
        def smallest(nums), do: Enum.min(nums)
        def largest(nums), do: Enum.max(nums)
      end
      """

      assert check(code) == []
    end

    test "passes code that sorts and takes multiple elements" do
      code = """
      defmodule GoodTake do
        def top_three(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.sort |> Enum.at pipeline" do
      code = """
      defmodule BadSort do
        def kth_largest(nums, k) do
          Enum.sort(nums, :desc) |> Enum.at(k - 1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_sort_then_at

      assert issue.message =~ "Enum.at/2"
      assert issue.meta.line != nil
    end

    test "detects nested Enum.at(Enum.sort(...))" do
      code = """
      defmodule BadNested do
        def median(nums) do
          mid = div(length(nums), 2)
          Enum.at(Enum.sort(nums), mid)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_sort_then_at
    end

    test "ignores Enum.at on non-sorted lists" do
      code = """
      defmodule SafeAt do
        def get_element(list, idx) do
          Enum.at(list, idx)
        end
      end
      """

      assert check(code) == []
    end
  end
end
