defmodule Credence.Semantic.FixErlangBitwiseBifFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixErlangBitwiseBif

  defp fix(source, message, line \\ 3) do
    FixErlangBitwiseBif.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  @bsl_input """
  defmodule Test do
    def left_shift(value, n) do
      bsl(value, n)
    end
  end
  """

  @bsl_expected """
  defmodule Test do
    def left_shift(value, n) do
      Bitwise.bsl(value, n)
    end
  end
  """

  @band_input """
  defmodule Test do
    def mask(value, n) do
      band(value, n)
    end
  end
  """

  @band_expected """
  defmodule Test do
    def mask(value, n) do
      Bitwise.band(value, n)
    end
  end
  """

  @or_input """
  defmodule Test do
    def combine(a, b) do
      a ||| b
    end
  end
  """

  @or_expected """
  defmodule Test do
    def combine(a, b) do
      Bitwise.bor(a, b)
    end
  end
  """

  @xor_input """
  defmodule Test do
    def diff(a, b) do
      a ^^^ b
    end
  end
  """

  @xor_expected """
  defmodule Test do
    def diff(a, b) do
      Bitwise.bxor(a, b)
    end
  end
  """

  test "fixes bsl to Bitwise.bsl" do
    message = "undefined function bsl/2"
    confirm_fix(fix(@bsl_input, message), @bsl_expected)
  end

  test "fixes band to Bitwise.band" do
    message = "undefined function band/2"
    confirm_fix(fix(@band_input, message, 3), @band_expected)
  end

  test "fixed output is well-formed (parses)" do
    message = "undefined function bsl/2"
    assert valid_syntax?(fix(@bsl_input, message))
  end

  test "does not double-prefix already-qualified call" do
    input = """
    defmodule Test do
      def shift(value, n) do
        Bitwise.bsl(value, n)
      end
    end
    """

    message = "undefined function bsl/2"
    # Should not change — already prefixed
    confirm_fix(fix(input, message), input)
  end

  test "fixes ||| to Bitwise.bor" do
    message = "undefined function |||/2"
    confirm_fix(fix(@or_input, message, 3), @or_expected)
  end

  test "fixes ^^^ to Bitwise.bxor" do
    message = "undefined function ^^^/2"
    confirm_fix(fix(@xor_input, message, 3), @xor_expected)
  end

  test "operator fix produces valid syntax" do
    message = "undefined function |||/2"
    assert valid_syntax?(fix(@or_input, message, 3))
  end

  test "fixes nested ||| and ^^^ operators" do
    input = """
    defmodule Test do
      def combine(a, b, c) do
        Enum.reduce([], 0, fn {x, y}, acc -> acc ||| (x ^^^ y) end)
      end
    end
    """

    message = "undefined function |||/2"
    result = fix(input, message, 3)
    assert valid_syntax?(result)
    assert result =~ "Bitwise.bor"
  end
end
