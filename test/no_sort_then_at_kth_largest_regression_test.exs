defmodule Credence.Pattern.NoSortThenAtKthLargestRegressionTest do
  use ExUnit.Case

  describe "kth_largest from pipeline log (idx=3)" do
    test "Enum.sort(&>=/2) |> Enum.at(rank - 1) is NOT flagged (variable index)" do
      # This is the exact code pattern from the pipeline log that was
      # falsely flagged by the old no_sort_then_at rule.
      # rank - 1 is a variable expression, not a literal 0 or -1.
      code = """
      defmodule KthLargestFinder do
        @doc \"\"\"
        Finds the k-th largest element in a list.
        \"\"\"
        @spec kth_largest(numbers :: [integer()], rank :: pos_integer()) :: integer()

        def kth_largest(numbers, rank) when is_list(numbers) and is_integer(rank) and rank > 0 do
          numbers
          |> Enum.sort(&>=/2)
          |> Enum.at(rank - 1)
        end
      end
      """

      {:ok, ast} = Sourceror.parse_string(code)
      issues = Credence.Pattern.NoSortThenAt.check(ast, [])

      assert issues == [],
             "Expected no issues for variable index (rank - 1), but got: #{inspect(issues)}"
    end

    test "Enum.sort(:desc) |> Enum.at(k - 1) is NOT flagged (variable index)" do
      code = """
      defmodule M do
        def kth(nums, k), do: Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end
      """

      {:ok, ast} = Sourceror.parse_string(code)
      issues = Credence.Pattern.NoSortThenAt.check(ast, [])

      assert issues == [],
             "Expected no issues for variable index (k - 1), but got: #{inspect(issues)}"
    end

    test "Enum.sort(:desc) |> Enum.at(0) IS still flagged (literal endpoint)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums, :desc) |> Enum.at(0)
      end
      """

      {:ok, ast} = Sourceror.parse_string(code)
      issues = Credence.Pattern.NoSortThenAt.check(ast, [])

      assert length(issues) > 0,
             "Expected literal 0 index to be flagged"
    end
  end
end
