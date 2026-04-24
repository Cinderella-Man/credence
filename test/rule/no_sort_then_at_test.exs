defmodule Credence.Rule.NoSortThenAtTest do
  use ExUnit.Case
  alias Credence.Issue

  describe "analyze/2 - NoSortThenAt Rule" do
    test "passes code that uses Enum.min or Enum.max" do
      code = """
      defmodule GoodCode do
        def smallest(nums), do: Enum.min(nums)
        def largest(nums), do: Enum.max(nums)
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end

    test "passes code that sorts and takes multiple elements" do
      code = """
      defmodule GoodTake do
        def top_three(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3)
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end

    test "detects Enum.sort |> Enum.at pipeline" do
      code = """
      defmodule BadSort do
        def kth_largest(nums, k) do
          Enum.sort(nums, :desc) |> Enum.at(k - 1)
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert %Issue{} = issue
      assert issue.rule == :no_sort_then_at
      assert issue.severity == :info
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

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert issue.rule == :no_sort_then_at
    end

    test "ignores Enum.at on non-sorted lists" do
      code = """
      defmodule SafeAt do
        def get_element(list, idx) do
          Enum.at(list, idx)
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end
  end
end
