defmodule Credence.Pattern.NoEnumAtNegativeIndexFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumAtNegativeIndex

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(NoEnumAtNegativeIndex, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ── Single -1 → List.last ──────────────────────────────────────────────

  describe "single -1 assignment → List.last" do
    test "standalone assignment" do
      input = """
      defmodule M do
        def f(list) do
          last = Enum.at(list, -1)
          last
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          last = List.last(list)
          last
        end
      end
      """

      assert fix(input) == expected
    end

    test "piped assignment" do
      input = """
      defmodule M do
        def f(list) do
          last = list |> Enum.at(-1)
          last
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          last = List.last(list)
          last
        end
      end
      """

      assert fix(input) == expected
    end

    test "two -1 on different lists" do
      input = """
      defmodule M do
        def f(a, b) do
          x = Enum.at(a, -1)
          y = Enum.at(b, -1)
          {x, y}
        end
      end
      """

      expected = """
      defmodule M do
        def f(a, b) do
          x = List.last(a)
          y = List.last(b)
          {x, y}
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "inline -1 (non-assignment) → List.last" do
    test "in if condition" do
      input = """
      defmodule M do
        def f(list) do
          if Enum.at(list, -1) == :done, do: :ok, else: :wait
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          if List.last(list) == :done, do: :ok, else: :wait
        end
      end
      """

      assert fix(input) == expected
    end

    test "piped in expression" do
      input = """
      defmodule M do
        def f(list), do: list |> Enum.sort() |> Enum.at(-1)
      end
      """

      expected = """
      defmodule M do
        def f(list), do: list |> Enum.sort() |> List.last()
      end
      """

      assert fix(input) == expected
    end
  end

  # ── Grouped reverse + pattern match ─────────────────────────────────────

  describe "grouped reverse + pattern match" do
    test "two accesses same list" do
      input = """
      defmodule M do
        def f(sorted) do
          last = Enum.at(sorted, -1)
          second = Enum.at(sorted, -2)
          {last, second}
        end
      end
      """

      expected = """
      defmodule M do
        def f(sorted) do
          sorted_reversed = Enum.reverse(sorted)
          [last, second | _] = sorted_reversed
          {last, second}
        end
      end
      """

      assert fix(input) == expected
    end

    test "three accesses same list" do
      input = """
      defmodule M do
        def f(nums) do
          a = Enum.at(nums, -1)
          b = Enum.at(nums, -2)
          c = Enum.at(nums, -3)
          {a, b, c}
        end
      end
      """

      expected = """
      defmodule M do
        def f(nums) do
          nums_reversed = Enum.reverse(nums)
          [a, b, c | _] = nums_reversed
          {a, b, c}
        end
      end
      """

      assert fix(input) == expected
    end

    test "non-consecutive indices fill gaps with _" do
      input = """
      defmodule M do
        def f(list) do
          last = Enum.at(list, -1)
          third = Enum.at(list, -3)
          {last, third}
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          list_reversed = Enum.reverse(list)
          [last, _, third | _] = list_reversed
          {last, third}
        end
      end
      """

      assert fix(input) == expected
    end

    test "single -2 gets reverse + pattern" do
      input = """
      defmodule M do
        def f(list) do
          second = Enum.at(list, -2)
          second
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          list_reversed = Enum.reverse(list)
          [_, second | _] = list_reversed
          second
        end
      end
      """

      assert fix(input) == expected
    end

    test "single -3 gets reverse + pattern" do
      input = """
      defmodule M do
        def f(list) do
          val = Enum.at(list, -3)
          val
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          list_reversed = Enum.reverse(list)
          [_, _, val | _] = list_reversed
          val
        end
      end
      """

      assert fix(input) == expected
    end

    test "depth 5 with gaps" do
      input = """
      defmodule M do
        def f(list) do
          a = Enum.at(list, -1)
          e = Enum.at(list, -5)
          {a, e}
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          list_reversed = Enum.reverse(list)
          [a, _, _, _, e | _] = list_reversed
          {a, e}
        end
      end
      """

      assert fix(input) == expected
    end

    test "pipe-form assignments grouped" do
      input = """
      defmodule M do
        def f(list) do
          last = list |> Enum.at(-1)
          second = list |> Enum.at(-2)
          {last, second}
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          list_reversed = Enum.reverse(list)
          [last, second | _] = list_reversed
          {last, second}
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ── Scope isolation ─────────────────────────────────────────────────────

  describe "scope isolation" do
    test "different functions not grouped" do
      input = """
      defmodule M do
        def foo(list) do
          a = Enum.at(list, -1)
          a
        end

        def bar(list) do
          b = Enum.at(list, -2)
          b
        end
      end
      """

      expected = """
      defmodule M do
        def foo(list) do
          a = List.last(list)
          a
        end

        def bar(list) do
          list_reversed = Enum.reverse(list)
          [_, b | _] = list_reversed
          b
        end
      end
      """

      assert fix(input) == expected
    end

    test "different list variables independent" do
      input = """
      defmodule M do
        def f(a, b) do
          x = Enum.at(a, -1)
          y = Enum.at(b, -1)
          {x, y}
        end
      end
      """

      expected = """
      defmodule M do
        def f(a, b) do
          x = List.last(a)
          y = List.last(b)
          {x, y}
        end
      end
      """

      assert fix(input) == expected
    end

    test "same list grouped + different list standalone" do
      input = """
      defmodule M do
        def f(sorted, other) do
          last = Enum.at(sorted, -1)
          second = Enum.at(sorted, -2)
          other_last = Enum.at(other, -1)
          {last, second, other_last}
        end
      end
      """

      expected = """
      defmodule M do
        def f(sorted, other) do
          sorted_reversed = Enum.reverse(sorted)
          [last, second | _] = sorted_reversed
          other_last = List.last(other)
          {last, second, other_last}
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ── Expression-form negative indices (non-assignment) ───────────────────
  # These prepend `<list>_reversed = Enum.reverse(<list>)` then a pattern match,
  # and substitute deterministic `<list>_negN` names — so we compare the whole
  # output exactly (the reverse assignment must come BEFORE the pattern match).

  describe "expression-form negative indices" do
    test "two negative indices in multiplication" do
      input = """
      defmodule M do
        def f(sorted) do
          result = Enum.at(sorted, -1) * Enum.at(sorted, -2)
          result
        end
      end
      """

      expected = """
      defmodule M do
        def f(sorted) do
          sorted_reversed = Enum.reverse(sorted)
          [sorted_neg1, sorted_neg2 | _] = sorted_reversed
          result = sorted_neg1 * sorted_neg2
          result
        end
      end
      """

      assert fix(input) == expected
    end

    test "single -2 in expression gets reverse + pattern" do
      input = """
      defmodule M do
        def f(sorted) do
          result = Enum.at(sorted, -2) + 1
          result
        end
      end
      """

      expected = """
      defmodule M do
        def f(sorted) do
          sorted_reversed = Enum.reverse(sorted)
          [_, sorted_neg2 | _] = sorted_reversed
          result = sorted_neg2 + 1
          result
        end
      end
      """

      assert fix(input) == expected
    end

    test "single -1 in expression becomes List.last" do
      input = """
      defmodule M do
        def f(list) do
          result = Enum.at(list, -1) + 1
          result
        end
      end
      """

      expected = """
      defmodule M do
        def f(list) do
          result = List.last(list) + 1
          result
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ── No-ops and edge cases ───────────────────────────────────────────────

  describe "no-ops" do
    test "positive index unchanged" do
      input = """
      defmodule M do
        def f(list) do
          first = Enum.at(list, 0)
          first
        end
      end
      """

      assert fix(input) == input
    end

    test "variable index unchanged" do
      input = """
      defmodule M do
        def f(list, i) do
          val = Enum.at(list, i)
          val
        end
      end
      """

      assert fix(input) == input
    end

    test "no Enum.at at all" do
      input = """
      defmodule M do
        def f(list), do: List.last(list)
      end
      """

      assert fix(input) == input
    end

    test "complex list expression skipped" do
      input = """
      defmodule M do
        def f(data) do
          a = Enum.at(Map.get(data, :items), -1)
          a
        end
      end
      """

      assert fix(input) == input
    end

    test "duplicate LHS variable names skipped for grouping" do
      input = """
      defmodule M do
        def f(list) do
          x = Enum.at(list, -1)
          x = Enum.at(list, -2)
          x
        end
      end
      """

      # Group invalid (duplicate :x): the -1 still becomes List.last (inline),
      # and the -2 gets the reverse + pattern (correctly ordered).
      expected = """
      defmodule M do
        def f(list) do
          x = List.last(list)
          list_reversed = Enum.reverse(list)
          [_, list_neg2 | _] = list_reversed
          x = list_neg2
          x
        end
      end
      """

      assert fix(input) == expected
    end
  end
end
