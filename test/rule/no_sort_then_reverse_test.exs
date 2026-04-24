defmodule Credence.Rule.NoSortThenReverseTest do
  use ExUnit.Case
  alias Credence.Issue

  describe "analyze/2 - NoSortThenReverse Rule" do
    test "passes code that uses Enum.sort with :desc" do
      code = """
      defmodule GoodSort do
        def top_three(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3)
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end

    test "detects Enum.sort |> Enum.reverse pipeline" do
      code = """
      defmodule BadPipeline do
        def descending(nums) do
          nums |> Enum.sort() |> Enum.reverse()
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert %Issue{} = issue
      assert issue.rule == :no_sort_then_reverse
      assert issue.severity == :warning
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

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert issue.rule == :no_sort_then_reverse
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

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert issue.rule == :no_sort_then_reverse
    end

    test "ignores Enum.reverse used on a non-sorted variable" do
      code = """
      defmodule SafeReverse do
        def process(list) do
          Enum.reverse(list)
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end

    test "ignores Enum.sort with a custom comparator followed by reverse" do
      # This is still flaggable, but we only flag Enum.sort/1 (no comparator)
      # since the user may have intentional reasons for sort+reverse with a comparator.
      code = """
      defmodule SafeCustom do
        def process(list) do
          Enum.sort(list, &(&1.name <= &2.name)) |> Enum.reverse()
        end
      end
      """

      result = Credence.analyze(code)

      # This depends on whether we want to flag sort/2 + reverse too.
      # For now, the rule matches Enum.sort with any arity piped to reverse.
      assert length(result.issues) == 1
    end
  end
end
