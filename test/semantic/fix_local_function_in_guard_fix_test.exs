defmodule Credence.Semantic.FixLocalFunctionInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [compiles?: 1, confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixLocalFunctionInGuard

  @real_message "cannot find or invoke local is_range/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: is_range(length_range)"

  defp fix(source, message \\ @real_message, line \\ 1) do
    FixLocalFunctionInGuard.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "replaces is_range with is_map in guard" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_integer(x), do: x
      def convert(x) when is_range(x), do: x
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_integer(x), do: x
      def convert(x) when is_map(x), do: x
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed and resolves the compile error" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
    end
    """

    refute compiles?(input)
    assert valid_syntax?(fix(input))
    assert compiles?(fix(input))
  end

  test "replaces in multi-guard clauses" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x) when is_integer(x), do: x
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_map(x) when is_integer(x), do: x
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "replaces in case clause guards" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) do
        case x do
          y when is_range(y) -> y
          _ -> nil
        end
      end
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) do
        case x do
          y when is_map(y) -> y
          _ -> nil
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves a variable named is_range untouched while fixing the real call" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
      def sum(is_range) when is_integer(is_range), do: is_range
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_map(x), do: x
      def sum(is_range) when is_integer(is_range), do: is_range
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves non-guard is_range calls untouched" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
      def describe(x), do: is_range(x)
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_map(x), do: x
      def describe(x), do: is_range(x)
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "no-op when the helper is not an is_map alias" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_struct(x, Range)

      def convert(x) when is_range(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the helper has multiple clauses" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(%Range{}), do: true
      defp is_range(_), do: false

      def convert(x) when is_range(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the helper clause is guarded" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x) when is_map(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when no local is_range/1 is defined" do
    input = """
    defmodule LocalFnInGuard do
      def convert(x) when is_range(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op on a two-argument is_range call in a guard" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x, y) when is_range(x, y), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when no is_range present" do
    input = """
    defmodule CleanExample do
      def convert(x) when is_map(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end
end
