defmodule Credence.Semantic.NoHallucinatedCryptoCompareFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedCryptoCompare

  @real_message ":crypto.compare/2 is undefined or private. Did you mean:\n\n    * hash_equals/2\n"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedCryptoCompare.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces :crypto.compare with :crypto.hash_equals" do
    input = """
    defmodule SecureToken do
      def verify_signature(expected, actual) do
        unless :crypto.compare(expected, actual) do
          {:error, :invalid_signature}
        else
          {:ok, :valid}
        end
      end
    end
    """

    expected = """
    defmodule SecureToken do
      def verify_signature(expected, actual) do
        unless :crypto.hash_equals(expected, actual) do
          {:error, :invalid_signature}
        else
          {:ok, :valid}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces :crypto.compare in a simple expression" do
    input = """
    defmodule TokenChecker do
      def equal?(a, b) do
        :crypto.compare(a, b)
      end
    end
    """

    expected = """
    defmodule TokenChecker do
      def equal?(a, b) do
        :crypto.hash_equals(a, b)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule X do
      def f(a, b), do: :crypto.compare(a, b)
    end
    """

    assert valid_syntax?(fix(input, @real_message, 2))
  end

  test "returns source unchanged when no :crypto.compare present" do
    input = """
    defmodule CleanExample do
      def verify(a, b), do: :crypto.hash_equals(a, b)
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
