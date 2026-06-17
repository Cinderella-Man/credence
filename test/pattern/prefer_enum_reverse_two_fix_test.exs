defmodule Credence.Pattern.PreferEnumReverseTwoFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferEnumReverseTwo

  describe "fix" do
    test "fixes simple Enum.reverse(acc) ++ tail" do
      input = "Enum.reverse(acc) ++ tail"

      expected = "Enum.reverse(acc, tail)"

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end

    test "fixes inside a module" do
      input = """
      defmodule OptimizationTarget do
        def merge(acc, tail) do
          Enum.reverse(acc) ++ tail
        end
      end
      """

      expected = """
      defmodule OptimizationTarget do
        def merge(acc, tail) do
          Enum.reverse(acc, tail)
        end
      end
      """

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end

    test "fixes with complex acc expression" do
      input = "Enum.reverse(Enum.sort(list)) ++ tail"

      expected = "Enum.reverse(Enum.sort(list), tail)"

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end

    test "fixes with complex tail expression" do
      input = "Enum.reverse(acc) ++ Enum.map(tail, &to_string/1)"

      expected = "Enum.reverse(acc, Enum.map(tail, &to_string/1))"

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end

    test "fixes chained ++ from inside out" do
      # Right-associative: Enum.reverse(a) ++ (Enum.reverse(b) ++ c)
      # Should become:     Enum.reverse(a, Enum.reverse(b, c))
      input = "Enum.reverse(a) ++ Enum.reverse(b) ++ c"

      expected = "Enum.reverse(a, Enum.reverse(b, c))"

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end

    test "fixes with explicit parentheses" do
      input = "(Enum.reverse(acc) ++ tail) ++ other"

      expected = "Enum.reverse(acc, tail) ++ other"

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end

    test "fixes multiple occurrences in different functions" do
      input = """
      defmodule M do
        def a(acc, t), do: Enum.reverse(acc) ++ t
        def b(acc, t), do: Enum.reverse(acc) ++ t
      end
      """

      expected = """
      defmodule M do
        def a(acc, t), do: Enum.reverse(acc, t)
        def b(acc, t), do: Enum.reverse(acc, t)
      end
      """

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end

    test "fixes real-world do_merge pattern" do
      input = """
      defmodule Merger do
        defp do_merge([], l2, acc), do: Enum.reverse(acc) ++ l2
        defp do_merge([h | t], l2, acc), do: do_merge(t, l2, [h | acc])
      end
      """

      expected = """
      defmodule Merger do
        defp do_merge([], l2, acc), do: Enum.reverse(acc, l2)
        defp do_merge([h | t], l2, acc), do: do_merge(t, l2, [h | acc])
      end
      """

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end

    test "does not modify code that is already correct" do
      code = """
      defmodule GoodCode do
        def merge(acc, tail), do: Enum.reverse(acc, tail)
      end
      """

      confirm_fix(fix(PreferEnumReverseTwo, code), code)
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

      expected = """
      defmodule M do
        def run(acc, tail) do
          x = 1 + 2
          result = Enum.reverse(acc, tail)
          {x, result}
        end
      end
      """

      confirm_fix(fix(PreferEnumReverseTwo, input), expected)
    end
  end
end
