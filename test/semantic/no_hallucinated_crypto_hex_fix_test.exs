defmodule Credence.Semantic.NoHallucinatedCryptoHexFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedCryptoHex

  @real_message ":crypto.hex/1 is undefined or private. Did you mean:\n\n    * hash/2\n    * hash/3\n"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedCryptoHex.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces :crypto.hex with Base.encode16" do
    input = """
    defmodule HallucinatedCryptoHex do
      def hex_encode(data) when is_binary(data) do
        :crypto.hex(data)
      end
    end
    """

    expected = """
    defmodule HallucinatedCryptoHex do
      def hex_encode(data) when is_binary(data) do
        Base.encode16(data)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces :crypto.hex in a simple expression" do
    input = """
    defmodule HexHelper do
      def encode(data), do: :crypto.hex(data)
    end
    """

    expected = """
    defmodule HexHelper do
      def encode(data), do: Base.encode16(data)
    end
    """

    confirm_fix(fix(input, @real_message, 2), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule X do
      def f(data), do: :crypto.hex(data)
    end
    """

    assert valid_syntax?(fix(input, @real_message, 2))
  end

  test "returns source unchanged when no :crypto.hex present" do
    input = """
    defmodule CleanExample do
      def encode(data), do: Base.encode16(data)
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
