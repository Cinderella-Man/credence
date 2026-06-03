defmodule Credence.Pattern.NoRemForParityCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRemForParityCheck

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRemForParityCheck.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoRemForParityCheck, code, [])

  describe "check" do
    test "detects rem(x, 2) == 0" do
      code = """
      defmodule M do
        def even?(x), do: rem(x, 2) == 0
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_rem_for_parity_check
    end

    test "detects rem(x, 2) != 0" do
      code = """
      defmodule M do
        def odd?(x), do: rem(x, 2) != 0
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects rem(x, 2) == 1" do
      code = """
      defmodule M do
        def odd?(x), do: rem(x, 2) == 1
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects rem(x, 2) != 1" do
      code = """
      defmodule M do
        def even?(x), do: rem(x, 2) != 1
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects reversed operand order: 0 == rem(x, 2)" do
      code = """
      defmodule M do
        def even?(x), do: 0 == rem(x, 2)
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects in pipe filter" do
      code = """
      defmodule M do
        def evens(list) do
          list |> Enum.filter(&(rem(&1, 2) == 0))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "ignores rem(x, 3) == 0 (not parity)" do
      code = """
      defmodule M do
        def divisible_by_3?(x), do: rem(x, 3) == 0
      end
      """

      assert check(code) == []
    end

    test "ignores rem(x, 2) == 2 (not 0 or 1)" do
      code = """
      defmodule M do
        def weird?(x), do: rem(x, 2) == 2
      end
      """

      assert check(code) == []
    end

    test "ignores Integer.is_even(x)" do
      code = """
      defmodule M do
        def even?(x), do: Integer.is_even(x)
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces rem(x, 2) == 0 with Integer.is_even(x)" do
      code = "rem(x, 2) == 0"
      result = fix(code)
      assert result =~ "Integer.is_even(x)"
      refute result =~ "rem("
    end

    test "replaces rem(x, 2) != 0 with Integer.is_odd(x)" do
      code = "rem(x, 2) != 0"
      result = fix(code)
      assert result =~ "Integer.is_odd(x)"
      refute result =~ "rem("
    end

    test "replaces rem(x, 2) == 1 with Integer.is_odd(x)" do
      code = "rem(x, 2) == 1"
      result = fix(code)
      assert result =~ "Integer.is_odd(x)"
    end

    test "replaces 0 == rem(x, 2) with Integer.is_even(x)" do
      code = "0 == rem(x, 2)"
      result = fix(code)
      assert result =~ "Integer.is_even(x)"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def evens(list) do
          Enum.filter(list, &(rem(&1, 2) == 0))
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.filter"
      assert result =~ "Integer.is_even"
      refute result =~ "rem("
    end

    test "round-trip: fixed code produces no issues" do
      code = "rem(x, 2) == 0"
      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoRemForParityCheck.check(ast, []) == []
    end

    test "inserts require Integer when module lacks it" do
      code = """
      defmodule M do
        def odd?(x), do: rem(x, 2) != 0
      end
      """

      result = fix(code)
      assert result =~ "require Integer"
      assert result =~ "Integer.is_odd(x)"
      refute result =~ "rem("
    end

    test "does not duplicate require Integer when already present" do
      code = """
      defmodule M do
        require Integer

        def odd?(x), do: rem(x, 2) != 0
      end
      """

      result = fix(code)
      assert result =~ "Integer.is_odd(x)"
      # Count occurrences — should be exactly 1
      occurrences = result |> String.split("require Integer") |> length() |> Kernel.-(1)
      assert occurrences == 1
    end

    test "inserts require Integer after @moduledoc" do
      code = """
      defmodule M do
        @moduledoc "Checks parity"

        def odd?(x), do: rem(x, 2) != 0
      end
      """

      result = fix(code)
      assert result =~ "require Integer"
      assert result =~ "Integer.is_odd(x)"
    end
  end
end
