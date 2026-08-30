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
      Elixir.Bitwise.bsl(value, n)
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
      Elixir.Bitwise.band(value, n)
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
      Elixir.Bitwise.bor(a, b)
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
      Elixir.Bitwise.bxor(a, b)
    end
  end
  """

  test "fixes bsl to Elixir.Bitwise.bsl" do
    message = "undefined function bsl/2"
    confirm_fix(fix(@bsl_input, message), @bsl_expected)
  end

  test "fixes band to Elixir.Bitwise.band" do
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
        value |> Elixir.Bitwise.band(1)
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
        IO.puts("bsl(value, n) shifts") && Elixir.Bitwise.bsl(value, n)
      end
    end
    """

    message = "undefined function bsl/2"
    confirm_fix(fix(input, message), expected)
  end

  test "uses the fully qualified Bitwise module when a local alias shadows Bitwise" do
    input = """
    defmodule FixErlangBitwiseBifShadowedImplementation do
      def bsl(_value, _n), do: :wrong
    end

    defmodule FixErlangBitwiseBifShadowedAliasFixture do
      alias FixErlangBitwiseBifShadowedImplementation, as: Bitwise
      def left_shift(value, n), do: bsl(value, n)
    end

    unless FixErlangBitwiseBifShadowedAliasFixture.left_shift(2, 3) == 16, do: raise("wrong shift")
    """

    expected = """
    defmodule FixErlangBitwiseBifShadowedImplementation do
      def bsl(_value, _n), do: :wrong
    end

    defmodule FixErlangBitwiseBifShadowedAliasFixture do
      alias FixErlangBitwiseBifShadowedImplementation, as: Bitwise
      def left_shift(value, n), do: Elixir.Bitwise.bsl(value, n)
    end

    unless FixErlangBitwiseBifShadowedAliasFixture.left_shift(2, 3) == 16, do: raise("wrong shift")
    """

    control = """
    defmodule FixErlangBitwiseBifShadowedAliasControl do
      def left_shift(value, n), do: Elixir.Bitwise.bsl(value, n)
    end

    unless FixErlangBitwiseBifShadowedAliasControl.left_shift(2, 3) == 16, do: raise("wrong shift")
    """

    fixed = fix(input, "undefined function bsl/2", 7)
    confirm_fix(fixed, expected)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(control)
  end

  test "leaves quoted bsl data on the diagnostic line untouched" do
    input = """
    defmodule FixErlangBitwiseBifQuotedDataFixture do
      def left_shift(value, n), do: {bsl(value, n), quote(do: bsl(1, 2))}
    end
    """

    expected = """
    defmodule FixErlangBitwiseBifQuotedDataFixture do
      def left_shift(value, n), do: {Elixir.Bitwise.bsl(value, n), quote(do: bsl(1, 2))}
    end
    """

    confirm_fix(fix(input, "undefined function bsl/2", 2), expected)
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
        a = Elixir.Bitwise.bsl(value, n)
        b = bsl(a, n)
        a + b
      end
    end
    """

    message = "undefined function bsl/2"
    confirm_fix(fix(input, message, 3), expected)
  end

  test "fixes ||| to Elixir.Bitwise.bor" do
    message = "undefined function |||/2"
    confirm_fix(fix(@or_input, message, 3), @or_expected)
  end

  test "fixes ^^^ to Elixir.Bitwise.bxor" do
    message = "undefined function ^^^/2"
    confirm_fix(fix(@xor_input, message, 3), @xor_expected)
  end

  test "fixes >>> to Elixir.Bitwise.bsr" do
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
        Elixir.Bitwise.bsr(a, b)
      end
    end
    """

    message = "undefined function >>>/2"
    confirm_fix(fix(input, message, 3), expected)
  end

  test "fixes unary ~~~ to Elixir.Bitwise.bnot" do
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
        Elixir.Bitwise.bnot(a)
      end
    end
    """

    message = "undefined function ~~~/1"
    confirm_fix(fix(input, message, 3), expected)
  end

  test "fixes every other admitted bitwise spelling" do
    cases = [
      {"bor", 2, "bor(5, 2)", "Elixir.Bitwise.bor(5, 2)", "Bor", 7},
      {"bsr", 2, "bsr(16, 2)", "Elixir.Bitwise.bsr(16, 2)", "Bsr", 4},
      {"bxor", 2, "bxor(5, 3)", "Elixir.Bitwise.bxor(5, 3)", "Bxor", 6},
      {"bnot", 1, "bnot(5)", "Elixir.Bitwise.bnot(5)", "Bnot", -6},
      {"&&&", 2, "5 &&& 3", "Elixir.Bitwise.band(5, 3)", "And", 1},
      {"<<<", 2, "2 <<< 3", "Elixir.Bitwise.bsl(2, 3)", "LeftShift", 16}
    ]

    for {spelling, arity, bad_expression, good_expression, suffix, value} <- cases do
      fixture_module = "FixErlangBitwiseBif#{suffix}Fixture"
      control_module = "FixErlangBitwiseBif#{suffix}Control"

      input = """
      defmodule #{fixture_module} do
        def value, do: #{bad_expression}
      end
      """

      expected = """
      defmodule #{fixture_module} do
        def value, do: #{good_expression}
      end
      """

      control = """
      defmodule #{control_module} do
        def value, do: #{good_expression}
      end

      unless #{control_module}.value() == #{value}, do: raise("wrong bitwise result")
      """

      fixed = fix(input, "undefined function #{spelling}/#{arity}", 2)

      fixed_with_witness =
        fixed <>
          "\nunless #{fixture_module}.value() == #{value}, do: raise(\"wrong bitwise result\")\n"

      confirm_fix(fixed, expected)
      assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed_with_witness)
      assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(control)
    end
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
        Enum.reduce([], 0, fn {x, y}, acc -> Elixir.Bitwise.bor(acc, x ^^^ y) end)
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
        Elixir.Bitwise.bor(x, y)
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
        Elixir.Bitwise.bsl(value, n)
      end

      def combine(a, b) do
        Elixir.Bitwise.bor(a, b)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(source), expected)
  end
end
