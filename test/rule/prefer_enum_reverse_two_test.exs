defmodule Credence.Rule.PreferEnumReverseTwoTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.PreferEnumReverseTwo.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.PreferEnumReverseTwo.fix(code, [])
  end

  defp assert_fixed(input) do
    result = fix(input)

    {:ok, ast} = Code.string_to_quoted(result)
    issues = Credence.Rule.PreferEnumReverseTwo.check(ast, [])

    assert issues == [],
           "Expected no issues after fix, got: #{inspect(issues)}\nFixed code:\n#{result}"

    result
  end

  describe "PreferEnumReverseTwo" do
    # ---- CHECK TESTS (unchanged from original) ----

    test "detects Enum.reverse(acc) ++ tail" do
      code = """
      defmodule OptimizationTarget do
        def merge(acc, tail) do
          Enum.reverse(acc) ++ tail
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :prefer_enum_reverse_two
      assert issue.message =~ "Enum.reverse(list1, list2)"
    end

    test "passes when using the optimized Enum.reverse/2" do
      code = """
      defmodule GoodCode do
        def merge(acc, tail), do: Enum.reverse(acc, tail)
      end
      """

      assert check(code) == []
    end

    test "ignores standard concatenation without reverse" do
      code = """
      defmodule StandardConcatenation do
        def combine(a, b), do: a ++ b
      end
      """

      assert check(code) == []
    end

    test "ignores Enum.reverse/1 when not used with ++" do
      code = """
      defmodule SimpleReverse do
        def flip(list), do: Enum.reverse(list)
      end
      """

      assert check(code) == []
    end

    # ---- FIX TESTS (new) ----

    test "fixes simple Enum.reverse(acc) ++ tail" do
      result = assert_fixed("Enum.reverse(acc) ++ tail")
      assert result =~ "Enum.reverse(acc, tail)"
    end

    test "fixes inside a module" do
      input = """
      defmodule OptimizationTarget do
        def merge(acc, tail) do
          Enum.reverse(acc) ++ tail
        end
      end
      """

      result = assert_fixed(input)
      assert result =~ "Enum.reverse(acc, tail)"
    end

    test "fixes with complex acc expression" do
      input = "Enum.reverse(Enum.sort(list)) ++ tail"
      result = assert_fixed(input)
      assert result =~ "Enum.reverse(Enum.sort(list), tail)"
    end

    test "fixes with complex tail expression" do
      input = "Enum.reverse(acc) ++ Enum.map(tail, &to_string/1)"
      result = assert_fixed(input)
      assert result =~ "Enum.reverse(acc, Enum.map(tail, &to_string/1))"
    end

    test "fixes chained ++ from inside out" do
      # Right-associative: Enum.reverse(a) ++ (Enum.reverse(b) ++ c)
      # Should become:     Enum.reverse(a, Enum.reverse(b, c))
      input = "Enum.reverse(a) ++ Enum.reverse(b) ++ c"
      result = assert_fixed(input)
      assert result =~ "Enum.reverse(a, Enum.reverse(b, c))"
    end

    test "fixes with explicit parentheses" do
      input = "(Enum.reverse(acc) ++ tail) ++ other"
      result = assert_fixed(input)
      # Inner pair fixed first: Enum.reverse(acc, tail) ++ other
      assert result =~ "Enum.reverse(acc, tail)"
    end

    test "fixes multiple occurrences in different functions" do
      input = """
      defmodule M do
        def a(acc, t), do: Enum.reverse(acc) ++ t
        def b(acc, t), do: Enum.reverse(acc) ++ t
      end
      """

      assert_fixed(input)
    end

    test "fixes real-world do_merge pattern" do
      input = """
      defmodule Merger do
        defp do_merge([], l2, acc), do: Enum.reverse(acc) ++ l2
        defp do_merge([h | t], l2, acc), do: do_merge(t, l2, [h | acc])
      end
      """

      result = assert_fixed(input)
      assert result =~ "Enum.reverse(acc, l2)"
    end

    test "does not modify code that is already correct" do
      input = """
      defmodule GoodCode do
        def merge(acc, tail), do: Enum.reverse(acc, tail)
      end
      """

      result = assert_fixed(input)
      assert result =~ "Enum.reverse(acc, tail)"
    end

    test "preserves other code around the fix" do
      input = """
      defmodule M do
        def run(acc, tail) do
          x = 1 + 2
          result = Enum.reverse(acc) ++ tail
          {x, result}
        end
      end
      """

      result = assert_fixed(input)
      assert result =~ "x = 1 + 2"
      assert result =~ "{x, result}"
      assert result =~ "Enum.reverse(acc, tail)"
    end
  end
end
