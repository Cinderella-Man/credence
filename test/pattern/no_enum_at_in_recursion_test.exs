defmodule Credence.Pattern.NoEnumAtInRecursionTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumAtInRecursion

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumAtInRecursion.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoEnumAtInRecursion, code, [])
  end

  describe "detects Enum.at with dynamic index in recursive functions" do
    test "flags two-pointer pattern with variable indices" do
      code = """
      defmodule Container do
        def max_area(heights) do
          do_max_area(heights, 0, length(heights) - 1, 0)
        end

        defp do_max_area(_heights, left, right, max) when left >= right, do: max

        defp do_max_area(heights, left, right, max) do
          left_h = Enum.at(heights, left)
          right_h = Enum.at(heights, right)
          area = (right - left) * min(left_h, right_h)
          new_max = max(max, area)

          if left_h < right_h do
            do_max_area(heights, left + 1, right, new_max)
          else
            do_max_area(heights, left, right - 1, new_max)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_enum_at_in_recursion))
      assert Enum.all?(issues, &(&1.message =~ "List.to_tuple/1"))
    end

    test "flags piped Enum.at in recursive function" do
      code = """
      defmodule Walker do
        def walk(list, idx, acc) when idx < 0, do: acc

        def walk(list, idx, acc) do
          val = list |> Enum.at(idx)
          walk(list, idx - 1, acc + val)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_at_in_recursion
    end

    test "flags Enum.at with arithmetic index in recursive function" do
      code = """
      defmodule SumPairs do
        def sum_pairs(list, left, right) when left >= right, do: 0

        def sum_pairs(list, left, right) do
          a = Enum.at(list, left)
          b = Enum.at(list, right - 1)
          a + b + sum_pairs(list, left + 1, right - 1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "flags recursive defp with single Enum.at" do
      code = """
      defmodule Acc do
        def run(list, idx) when idx < 0, do: 0

        def run(list, idx) do
          Enum.at(list, idx) + run(list, idx - 1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end
  end

  describe "ignores non-recursive functions" do
    test "does not flag non-recursive function with dynamic Enum.at" do
      code = """
      defmodule Simple do
        def get(list, idx) do
          Enum.at(list, idx)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "ignores safe patterns" do
    test "does not flag Enum.at with literal integer index in recursion" do
      code = """
      defmodule Safe do
        def walk(list, acc) when list == [], do: acc

        def walk(list, acc) do
          first = Enum.at(list, 0)
          walk(tl(list), acc + first)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag code using elem/tuple" do
      code = """
      defmodule Fast do
        def run(tuple, idx, acc) when idx < 0, do: acc

        def run(tuple, idx, acc) do
          val = elem(tuple, idx)
          run(tuple, idx - 1, acc + val)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag midpoint expressions (handled by no_enum_at_binary_search)" do
      code = """
      defmodule Search do
        def search(list, target, low, high) when low <= high do
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> search(list, target, mid + 1, high)
            true -> search(list, target, low, mid - 1)
          end
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "check-only: no auto-fix" do
    test "fix returns source unchanged" do
      code = """
      defmodule Walker do
        def walk(list, idx, acc) when idx < 0, do: acc

        def walk(list, idx, acc) do
          val = Enum.at(list, idx)
          walk(list, idx - 1, acc + val)
        end
      end
      """

      result = fix(code)
      assert result == code
    end
  end
end
