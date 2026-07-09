defmodule Credence.Semantic.NoHallucinatedBaseHexEncodeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedBaseHexEncode

  @real_message "Base.hex_encode/1 is undefined or private. Did you mean:\n\n    * encode16/2\n"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedBaseHexEncode.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces Base.hex_encode() with Base.encode16(case: :lower) in pipe" do
    input = """
    defmodule HallucinatedBaseHexEncode do
      def encode(data) do
        :crypto.hash(:sha256, data) |> Base.hex_encode()
      end
    end
    """

    expected = """
    defmodule HallucinatedBaseHexEncode do
      def encode(data) do
        :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces Base.hex_encode(arg) with Base.encode16(arg, case: :lower)" do
    input = """
    defmodule Encoder do
      def to_hex(data) do
        Base.hex_encode(data)
      end
    end
    """

    expected = """
    defmodule Encoder do
      def to_hex(data) do
        Base.encode16(data, case: :lower)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces Base.hex_encode(arg, opts) with Base.encode16(arg, opts)" do
    input = """
    defmodule Encoder do
      def to_hex(data) do
        Base.hex_encode(data, case: :upper)
      end
    end
    """

    expected = """
    defmodule Encoder do
      def to_hex(data) do
        Base.encode16(data, case: :upper)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule HallucinatedBaseHexEncode do
      def encode(data) do
        :crypto.hash(:sha256, data) |> Base.hex_encode()
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged when no Base.hex_encode present" do
    input = """
    defmodule CleanExample do
      def encode(data) do
        Base.encode16(data, case: :lower)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
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
