defmodule Credence.Rule.NoSortThenReverseTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoSortThenReverse.check(ast, [])
  end

  describe "NoSortThenReverse" do
    test "passes code that uses Enum.sort with :desc" do
      code = """
      defmodule GoodSort do
        def top_three(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.sort |> Enum.reverse pipeline" do
      code = """
      defmodule BadPipeline do
        def descending(nums) do
          nums |> Enum.sort() |> Enum.reverse()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_sort_then_reverse

      assert issue.message =~ "Enum.sort(list, :desc)"
      assert issue.meta.line != nil
    end

    test "detects nested call Enum.reverse(Enum.sort(...))" do
      code = """
      defmodule BadNested do
        def descending(nums) do
          Enum.reverse(Enum.sort(nums))
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_sort_then_reverse
    end

    test "detects variable-mediated sort then reverse" do
      code = """
      defmodule BadVariable do
        def max_product(nums) do
          sorted = Enum.sort(nums)
          [min1, min2 | _] = sorted
          [max1, max2, max3 | _] = Enum.reverse(sorted)
          max(min1 * min2 * max1, max1 * max2 * max3)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_sort_then_reverse
    end

    test "ignores Enum.reverse used on a non-sorted variable" do
      code = """
      defmodule SafeReverse do
        def process(list) do
          Enum.reverse(list)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.sort with a custom comparator followed by reverse" do
      code = """
      defmodule CustomSort do
        def process(list) do
          Enum.sort(list, &(&1.name <= &2.name)) |> Enum.reverse()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end
  end
end
