defmodule Credence.Semantic.FixLocalFunctionInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

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

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
    end
    """

    assert valid_syntax?(fix(input))
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
