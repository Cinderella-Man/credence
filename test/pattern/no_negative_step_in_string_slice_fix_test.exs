defmodule Credence.Pattern.NoNegativeStepInStringSliceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoNegativeStepInStringSlice

  describe "NoNegativeStepInStringSlice fix" do
    test "rewrites String.slice(str, n..-1) to String.slice(str, n..-1//1)" do
      input = """
      defmodule M do
        @doc false
        def suffix(str, n) when is_binary(str) and is_integer(n) do
          String.slice(str, n..-1)
        end
      end
      """

      expected = """
      defmodule M do
        @doc false
        def suffix(str, n) when is_binary(str) and is_integer(n) do
          String.slice(str, n..-1//1)
        end
      end
      """

      confirm_fix(fix(NoNegativeStepInStringSlice, input), expected)
    end

    test "rewrites String.slice(str, 0..-1) with literal start" do
      input = """
      defmodule M do
        def full(str) do
          String.slice(str, 0..-1)
        end
      end
      """

      expected = """
      defmodule M do
        def full(str) do
          String.slice(str, 0..-1//1)
        end
      end
      """

      confirm_fix(fix(NoNegativeStepInStringSlice, input), expected)
    end

    test "rewrites String.slice(str, 2..-1) with positive literal start" do
      input = """
      defmodule M do
        def skip_two(str) do
          String.slice(str, 2..-1)
        end
      end
      """

      expected = """
      defmodule M do
        def skip_two(str) do
          String.slice(str, 2..-1//1)
        end
      end
      """

      confirm_fix(fix(NoNegativeStepInStringSlice, input), expected)
    end

    test "rewrites multiple occurrences in one file" do
      input = """
      defmodule M do
        def a(str, n) do
          x = String.slice(str, n..-1)
          y = String.slice(str, 0..-1)
          {x, y}
        end
      end
      """

      expected = """
      defmodule M do
        def a(str, n) do
          x = String.slice(str, n..-1//1)
          y = String.slice(str, 0..-1//1)
          {x, y}
        end
      end
      """

      confirm_fix(fix(NoNegativeStepInStringSlice, input), expected)
    end

    test "does not modify String.slice with explicit step" do
      code = """
      defmodule M do
        def suffix(str, n) do
          String.slice(str, n..-1//1)
        end
      end
      """

      confirm_fix(fix(NoNegativeStepInStringSlice, code), code)
    end

    test "does not modify String.slice with non-negative range" do
      code = """
      defmodule M do
        def mid(str) do
          String.slice(str, 1..3)
        end
      end
      """

      confirm_fix(fix(NoNegativeStepInStringSlice, code), code)
    end

    test "does not modify non-String.slice calls" do
      code = """
      defmodule M do
        def range(n) do
          Enum.to_list(n..-1)
        end
      end
      """

      confirm_fix(fix(NoNegativeStepInStringSlice, code), code)
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule M do
        def suffix(str, n) do
          String.slice(str, n..-1)
        end
      end
      """

      assert check(NoNegativeStepInStringSlice, fix(NoNegativeStepInStringSlice, code)) == []
    end
  end
end
