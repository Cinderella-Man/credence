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

  test "fixes a no-parens bsl call" do
    input = """
    defmodule Test do
      def left_shift(value, n) do
        bsl value, n
      end
    end
    """

    message = "undefined function bsl/2"
    confirm_fix(fix(input, message), @bsl_expected)
  end

  test "fixes a piped band call" do
    input = """
    defmodule Test do
      def low_bit(value) do
        value |> band(1)
      end
    end
    """

    expected = """
    defmodule Test do
      def low_bit(value) do
        value |> Bitwise.band(1)
      end
    end
    """

    message = "undefined function band/2"
    confirm_fix(fix(input, message), expected)
  end

  test "does not rewrite bsl inside a string literal on the flagged line" do
    input = """
    defmodule Test do
      def left_shift(value, n) do
        IO.puts("bsl(value, n) shifts") && bsl(value, n)
      end
    end
    """

    expected = """
    defmodule Test do
      def left_shift(value, n) do
        IO.puts("bsl(value, n) shifts") && Bitwise.bsl(value, n)
      end
    end
    """

    message = "undefined function bsl/2"
    confirm_fix(fix(input, message), expected)
  end

  test "leaves bare bsl calls on other lines untouched" do
    # In production every call site carries its own diagnostic; the fix for
    # one diagnostic must only rewrite that diagnostic's line.
    input = """
    defmodule Test do
      def double_shift(value, n) do
        a = bsl(value, n)
        b = bsl(a, n)
        a + b
      end
    end
    """

    expected = """
    defmodule Test do
      def double_shift(value, n) do
        a = Bitwise.bsl(value, n)
        b = bsl(a, n)
        a + b
      end
    end
    """

    message = "undefined function bsl/2"
    confirm_fix(fix(input, message, 3), expected)
  end

  test "fixes ||| to Bitwise.bor" do
    message = "undefined function |||/2"
    confirm_fix(fix(@or_input, message, 3), @or_expected)
  end

  test "fixes ^^^ to Bitwise.bxor" do
    message = "undefined function ^^^/2"
    confirm_fix(fix(@xor_input, message, 3), @xor_expected)
  end

  test "fixes >>> to Bitwise.bsr" do
    input = """
    defmodule Test do
      def shift_right(a, b) do
        a >>> b
      end
    end
    """

    expected = """
    defmodule Test do
      def shift_right(a, b) do
        Bitwise.bsr(a, b)
      end
    end
    """

    message = "undefined function >>>/2"
    confirm_fix(fix(input, message, 3), expected)
  end

  test "fixes unary ~~~ to Bitwise.bnot" do
    input = """
    defmodule Test do
      def invert(a) do
        ~~~a
      end
    end
    """

    expected = """
    defmodule Test do
      def invert(a) do
        Bitwise.bnot(a)
      end
    end
    """

    message = "undefined function ~~~/1"
    confirm_fix(fix(input, message, 3), expected)
  end

  test "operator fix produces valid syntax" do
    message = "undefined function |||/2"
    assert valid_syntax?(fix(@or_input, message, 3))
  end

  test "fixes nested ||| without touching the ^^^ on the same line" do
    # The ^^^ carries its own diagnostic and is fixed by its own pass.
    input = """
    defmodule Test do
      def combine(a, b, c) do
        Enum.reduce([], 0, fn {x, y}, acc -> acc ||| (x ^^^ y) end)
      end
    end
    """

    expected = """
    defmodule Test do
      def combine(a, b, c) do
        Enum.reduce([], 0, fn {x, y}, acc -> Bitwise.bor(acc, x ^^^ y) end)
      end
    end
    """

    message = "undefined function |||/2"
    confirm_fix(fix(input, message, 3), expected)
  end

  test "leaves a custom ||| operator defined in another module untouched" do
    # Module MyOps defines |||; module Test uses it without importing it, so
    # the diagnostic points at Test's line. Rewriting MyOps' def head would
    # destroy valid code.
    input = """
    defmodule MyOps do
      def a ||| b, do: {a, b}
    end

    defmodule Test do
      def combine(x, y) do
        x ||| y
      end
    end
    """

    expected = """
    defmodule MyOps do
      def a ||| b, do: {a, b}
    end

    defmodule Test do
      def combine(x, y) do
        Bitwise.bor(x, y)
      end
    end
    """

    message = "undefined function |||/2"
    confirm_fix(fix(input, message, 7), expected)
  end

  test "returns source unchanged when the diagnostic line has no matching call" do
    message = "undefined function bsl/2"
    confirm_fix(fix(@bsl_input, message, 2), @bsl_input)
  end

  test "end-to-end: the semantic phase repairs real bitwise diagnostics" do
    source = """
    defmodule FixErlangBitwiseBifFixE2E do
      def left_shift(value, n) do
        bsl(value, n)
      end

      def combine(a, b) do
        a ||| b
      end
    end
    """

    expected = """
    defmodule FixErlangBitwiseBifFixE2E do
      def left_shift(value, n) do
        Bitwise.bsl(value, n)
      end

      def combine(a, b) do
        Bitwise.bor(a, b)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(source), expected)
  end
end
