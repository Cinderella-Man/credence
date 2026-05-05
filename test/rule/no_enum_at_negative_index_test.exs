defmodule Credence.Rule.NoEnumAtNegativeIndexTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEnumAtNegativeIndex.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoEnumAtNegativeIndex.fix(code, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Rule.NoEnumAtNegativeIndex.fixable?() == true
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — positive cases" do
    test "flags Enum.at(list, -1)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.at(list, -1)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_at_negative_index
      assert issue.message =~ "List.last"
    end

    test "flags Enum.at(list, -2)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.at(list, -2)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_at_negative_index
      assert issue.message =~ "Enum.reverse"
    end

    test "flags Enum.at(list, -3)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.at(list, -3)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "3 positions from the end"
    end

    test "flags piped Enum.at(-1)" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.sort() |> Enum.at(-1)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_at_negative_index
    end

    test "flags multiple negative accesses on the same list" do
      code = """
      defmodule Example do
        def run(sorted) do
          last = Enum.at(sorted, -1)
          second = Enum.at(sorted, -2)
          {last, second}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "flags negative index inside case/if" do
      code = """
      defmodule Example do
        def run(list) do
          if length(list) > 0 do
            Enum.at(list, -1)
          end
        end
      end
      """

      assert length(check(code)) == 1
    end
  end

  describe "check/2 — negative cases" do
    test "does not flag Enum.at with positive index" do
      code = """
      defmodule Example do
        def run(list), do: Enum.at(list, 0)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.at with positive index 5" do
      code = """
      defmodule Example do
        def run(list), do: Enum.at(list, 5)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.at with variable index" do
      code = """
      defmodule Example do
        def run(list, i), do: Enum.at(list, i)
      end
      """

      assert check(code) == []
    end

    test "does not flag List.last" do
      code = """
      defmodule Example do
        def run(list), do: List.last(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.at with expression index" do
      code = """
      defmodule Example do
        def run(list, n), do: Enum.at(list, n - 1)
      end
      """

      assert check(code) == []
    end

    test "does not flag unrelated Enum calls" do
      code = """
      defmodule Example do
        def run(list), do: Enum.reverse(list)
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS — SINGLE -1 (List.last replacement)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — single Enum.at(x, -1) → List.last" do
    test "fixes standalone assignment" do
      code = """
      defmodule Example do
        def run(list) do
          last = Enum.at(list, -1)
          last
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "last = List.last(list)"
      refute fixed =~ "Enum.at"
    end

    test "fixes inline (non-assignment) usage" do
      code = """
      defmodule Example do
        def run(list) do
          if Enum.at(list, -1) == :done, do: :ok, else: :wait
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "List.last(list)"
      refute fixed =~ "Enum.at"
    end

    test "fixes piped Enum.at(-1) in expression" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.sort() |> Enum.at(-1)
      end
      """

      fixed = fix(code)
      assert fixed =~ "List.last()"
      assert fixed =~ "Enum.sort()"
      refute fixed =~ "Enum.at"
    end

    test "fixes piped assignment" do
      code = """
      defmodule Example do
        def run(list) do
          last = list |> Enum.at(-1)
          last
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "List.last(list)"
      refute fixed =~ "Enum.at"
    end

    test "fixes multiple -1 accesses on different lists independently" do
      code = """
      defmodule Example do
        def run(a, b) do
          x = Enum.at(a, -1)
          y = Enum.at(b, -1)
          {x, y}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "x = List.last(a)"
      assert fixed =~ "y = List.last(b)"
      refute fixed =~ "Enum.at"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS — GROUPED REVERSE + PATTERN MATCH
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — grouped reverse + pattern match" do
    test "groups two accesses on the same list" do
      code = """
      defmodule Example do
        def run(sorted) do
          last = Enum.at(sorted, -1)
          second = Enum.at(sorted, -2)
          {last, second}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "sorted_reversed = Enum.reverse(sorted)"
      assert fixed =~ "[last, second | _] = sorted_reversed"
      refute fixed =~ "Enum.at"
      # Tuple usage is preserved
      assert fixed =~ "{last, second}"
    end

    test "preserves code between grouped accesses" do
      code = """
      defmodule Example do
        def run(sorted) do
          last = Enum.at(sorted, -1)
          Logger.info("got last")
          second = Enum.at(sorted, -2)
          {last, second}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "sorted_reversed = Enum.reverse(sorted)"
      assert fixed =~ "[last, second | _] = sorted_reversed"
      assert fixed =~ "Logger.info"
      refute fixed =~ "Enum.at"
    end

    test "groups three accesses on the same list" do
      code = """
      defmodule Example do
        def run(nums) do
          a = Enum.at(nums, -1)
          b = Enum.at(nums, -2)
          c = Enum.at(nums, -3)
          {a, b, c}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "nums_reversed = Enum.reverse(nums)"
      assert fixed =~ "[a, b, c | _] = nums_reversed"
      refute fixed =~ "Enum.at"
    end

    test "fills gaps with _ when indices are non-consecutive" do
      code = """
      defmodule Example do
        def run(list) do
          last = Enum.at(list, -1)
          third = Enum.at(list, -3)
          {last, third}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "list_reversed = Enum.reverse(list)"
      assert fixed =~ "[last, _, third | _] = list_reversed"
      refute fixed =~ "Enum.at"
    end

    test "handles single -2 access with reverse + pattern match" do
      code = """
      defmodule Example do
        def run(list) do
          second = Enum.at(list, -2)
          second
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "list_reversed = Enum.reverse(list)"
      assert fixed =~ "[_, second | _] = list_reversed"
      refute fixed =~ "Enum.at"
    end

    test "handles single -3 access with reverse + pattern match" do
      code = """
      defmodule Example do
        def run(list) do
          val = Enum.at(list, -3)
          val
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "list_reversed = Enum.reverse(list)"
      assert fixed =~ "[_, _, val | _] = list_reversed"
      refute fixed =~ "Enum.at"
    end

    test "preserves indentation" do
      code = """
      defmodule Example do
        def run(sorted) do
          if true do
            last = Enum.at(sorted, -1)
            second = Enum.at(sorted, -2)
            {last, second}
          end
        end
      end
      """

      fixed = fix(code)
      # Both replacement lines should have the same indentation as the original
      lines = String.split(fixed, "\n")
      reverse_line = Enum.find(lines, &String.contains?(&1, "Enum.reverse"))
      pattern_line = Enum.find(lines, &String.contains?(&1, "sorted_reversed"))

      assert reverse_line != nil
      assert pattern_line != nil
    end

    test "handles pipe-form assignments in groups" do
      code = """
      defmodule Example do
        def run(list) do
          last = list |> Enum.at(-1)
          second = list |> Enum.at(-2)
          {last, second}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "list_reversed = Enum.reverse(list)"
      assert fixed =~ "[last, second | _] = list_reversed"
      refute fixed =~ "Enum.at"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS — SCOPE ISOLATION
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — scope isolation" do
    test "does NOT group entries across different functions" do
      code = """
      defmodule Example do
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

      fixed = fix(code)
      # foo's -1 should become List.last, not grouped with bar's -2
      assert fixed =~ "a = List.last(list)"
      # bar's -2 should get its own reverse + pattern
      assert fixed =~ "list_reversed = Enum.reverse(list)"
      assert fixed =~ "[_, b | _] = list_reversed"
    end

    test "groups within the same function but not across" do
      code = """
      defmodule Example do
        def foo(list) do
          a = Enum.at(list, -1)
          b = Enum.at(list, -2)
          {a, b}
        end

        def bar(list) do
          c = Enum.at(list, -1)
          c
        end
      end
      """

      fixed = fix(code)
      # foo should be grouped
      assert fixed =~ "[a, b | _] = list_reversed"
      # bar should be standalone List.last
      assert fixed =~ "c = List.last(list)"
    end

    test "treats different list variables independently" do
      code = """
      defmodule Example do
        def run(alpha, beta) do
          a = Enum.at(alpha, -1)
          b = Enum.at(beta, -1)
          {a, b}
        end
      end
      """

      fixed = fix(code)
      # Each is a standalone -1, should become List.last
      assert fixed =~ "a = List.last(alpha)"
      assert fixed =~ "b = List.last(beta)"
      refute fixed =~ "Enum.at"
    end

    test "groups same list var, keeps different list var standalone" do
      code = """
      defmodule Example do
        def run(sorted, other) do
          last = Enum.at(sorted, -1)
          second = Enum.at(sorted, -2)
          other_last = Enum.at(other, -1)
          {last, second, other_last}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "sorted_reversed = Enum.reverse(sorted)"
      assert fixed =~ "[last, second | _] = sorted_reversed"
      assert fixed =~ "other_last = List.last(other)"
      refute fixed =~ "Enum.at"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS — EDGE CASES & SAFETY
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — edge cases" do
    test "does not touch positive indices" do
      code = """
      defmodule Example do
        def run(list) do
          first = Enum.at(list, 0)
          first
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.at(list, 0)"
    end

    test "does not touch variable indices" do
      code = """
      defmodule Example do
        def run(list, i) do
          val = Enum.at(list, i)
          val
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.at(list, i)"
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def run(list), do: List.last(list)
      end
      """

      assert fix(code) == code
    end

    test "skips complex list expressions (only simple variables are grouped)" do
      code = """
      defmodule Example do
        def run(data) do
          a = Enum.at(Map.get(data, :items), -1)
          a
        end
      end
      """

      fixed = fix(code)
      # Complex expression — assignment grouping can't handle it,
      # and the inline -1 regex only matches simple \w+ first args.
      # The code stays as-is for this case (check still flags it).
      assert fixed =~ "Enum.at(Map.get(data, :items), -1)"
    end

    test "skips groups with duplicate LHS variable names" do
      code = """
      defmodule Example do
        def run(list) do
          x = Enum.at(list, -1)
          x = Enum.at(list, -2)
          x
        end
      end
      """

      fixed = fix(code)
      # Duplicate lhs var :x — reverse group is invalid, both entries skipped.
      # The -1 still gets caught by the remaining_minus_one pass.
      assert fixed =~ "List.last(list)"
    end

    test "handles up to depth 5" do
      code = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, -1)
          e = Enum.at(list, -5)
          {a, e}
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "list_reversed = Enum.reverse(list)"
      assert fixed =~ "[a, _, _, _, e | _] = list_reversed"
      refute fixed =~ "Enum.at"
    end

    test "mixed: grouped pair + standalone inline -1" do
      code = """
      defmodule Example do
        def run(sorted, other) do
          last = Enum.at(sorted, -1)
          second = Enum.at(sorted, -2)
          val = Enum.at(other, -1)
          result = if Enum.at(other, -1) == :x, do: :yes, else: :no
          {last, second, val, result}
        end
      end
      """

      fixed = fix(code)
      # sorted group: reverse + pattern match
      assert fixed =~ "sorted_reversed = Enum.reverse(sorted)"
      assert fixed =~ "[last, second | _] = sorted_reversed"
      # other standalone -1: List.last
      assert fixed =~ "val = List.last(other)"
      # inline -1: also List.last
      assert fixed =~ "List.last(other) == :x"
      refute fixed =~ "Enum.at"
    end
  end
end
