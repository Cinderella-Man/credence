defmodule Credence.Semantic.NoDefineMatchFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDefineMatchFn

  @real_message "imported Kernel.match?/2 conflicts with local function"

  defp fix(source, message, line \\ 1) do
    NoDefineMatchFn.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "renames match?/2 to match_pattern?/2 in full module" do
    input = """
    defmodule Example do
      def check(a, b) do
        match?(a, b)
      end

      defp match?(a, b) do
        a == b
      end
    end
    """

    expected = """
    defmodule Example do
      def check(a, b) do
        match_pattern?(a, b)
      end

      defp match_pattern?(a, b) do
        a == b
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "renames match?/2 to match_pattern?/2 in single-clause module" do
    input = """
    defmodule Example do
      def check(a, b), do: match?(a, b)
      defp match?(a, b), do: a == b
    end
    """

    expected = """
    defmodule Example do
      def check(a, b), do: match_pattern?(a, b)
      defp match_pattern?(a, b), do: a == b
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def check(a, b), do: match?(a, b)
      defp match?(a, b), do: a == b
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no match? conflict" do
    input = """
    defmodule CleanExample do
      def hello, do: Kernel.match?(:ok, :ok)
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
