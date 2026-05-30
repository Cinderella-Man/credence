defmodule Credence.Pattern.NoManualTopKReduceTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoManualTopKReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualTopKReduce.check(ast, [])
  end

  describe "check — must fire" do
    test "detects manual two-smallest tracking via reduce with cond" do
      code = """
      defmodule BadTwoSmallest do
        def sum_of_two_smallest(list) do
          [first, second | rest] = list
          {min1, min2} = if first <= second, do: {first, second}, else: {second, first}

          {smallest, second_smallest} =
            Enum.reduce(rest, {min1, min2}, fn number, {current_smallest, current_second_smallest} ->
              cond do
                number < current_smallest -> {number, current_smallest}
                number < current_second_smallest -> {current_smallest, number}
                true -> {current_smallest, current_second_smallest}
              end
            end)

          smallest + second_smallest
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_manual_top_k_reduce
      assert issue.message =~ "extreme values"
    end

    test "detects manual two-largest tracking via reduce with cond" do
      code = """
      defmodule BadTwoLargest do
        def sum_of_two_largest(list) do
          [first, second | rest] = list
          {max1, max2} = if first >= second, do: {first, second}, else: {second, first}

          {largest, second_largest} =
            Enum.reduce(rest, {max1, max2}, fn number, {a, b} ->
              cond do
                number > a -> {number, a}
                number > b -> {a, number}
                true -> {a, b}
              end
            end)

          largest + second_largest
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_top_k_reduce
    end

    test "detects two instances in the same module" do
      code = """
      defmodule BadTwo do
        def smallest_pair(list) do
          [a, b | rest] = list
          {m1, m2} = if a <= b, do: {a, b}, else: {b, a}

          Enum.reduce(rest, {m1, m2}, fn x, {s1, s2} ->
            cond do
              x < s1 -> {x, s1}
              x < s2 -> {s1, x}
              true -> {s1, s2}
            end
          end)
        end

        def largest_pair(list) do
          [a, b | rest] = list
          {m1, m2} = if a >= b, do: {a, b}, else: {b, a}

          Enum.reduce(rest, {m1, m2}, fn x, {s1, s2} ->
            cond do
              x > s1 -> {x, s1}
              x > s2 -> {s1, x}
              true -> {s1, s2}
            end
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end
  end

  describe "check — must NOT fire" do
    test "passes code that uses Enum.sort |> Enum.take |> Enum.sum" do
      code = """
      defmodule GoodSortTake do
        def sum_of_two_smallest(list) do
          list |> Enum.sort() |> Enum.take(2) |> Enum.sum()
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses Enum.min/1" do
      code = """
      defmodule GoodMin do
        def min_value(list) do
          Enum.min(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses reduce for sum" do
      code = """
      defmodule GoodSum do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses reduce with map accumulator" do
      code = """
      defmodule GoodMapReduce do
        def build_map(list) do
          Enum.reduce(list, %{}, fn x, acc -> Map.put(acc, x, true) end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses reduce with tuple for non-extreme tracking" do
      code = """
      defmodule GoodTupleReduce do
        def track(list) do
          Enum.reduce(list, {0, 0}, fn x, {sum, count} ->
            {sum + x, count + 1}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses reduce with tuple and if (not cond)" do
      code = """
      defmodule GoodTupleIf do
        def track(list) do
          Enum.reduce(list, {0, 0}, fn x, {min, max} ->
            if x < min, do: {x, max}, else: {min, x}
          end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
