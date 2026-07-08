defmodule Credence.Syntax.FixPythonFormatInStringInterpolationFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixPythonFormatInStringInterpolation

  defp analyze(code), do: FixPythonFormatInStringInterpolation.analyze(code)
  defp fix(code), do: FixPythonFormatInStringInterpolation.fix(code)

  # ═══════════════════════════════════════════════════════════════════
  # FIXES — Python-style format specifier
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes Python-style format specifier" do
    test "cents_part:02" do
      confirm_fix(
        fix(~S'"#{cents_part:02}"'),
        ~S'"#{String.pad_leading(Integer.to_string(cents_part), 2, "0")}"'
      )
    end

    test "n:05" do
      confirm_fix(
        fix(~S'"#{n:05}"'),
        ~S'"#{String.pad_leading(Integer.to_string(n), 5, "0")}"'
      )
    end

    test "x:01" do
      confirm_fix(
        fix(~S'"#{x:01}"'),
        ~S'"#{String.pad_leading(Integer.to_string(x), 1, "0")}"'
      )
    end

    test "val:010" do
      confirm_fix(
        fix(~S'"#{val:010}"'),
        ~S'"#{String.pad_leading(Integer.to_string(val), 10, "0")}"'
      )
    end

    test "multiple on same line" do
      confirm_fix(
        fix(~S'"#{a:02}-#{b:03}"'),
        ~S'"#{String.pad_leading(Integer.to_string(a), 2, "0")}-#{String.pad_leading(Integer.to_string(b), 3, "0")}"'
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXES — full module context
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes in full module context" do
    test "format_price module" do
      input = """
      defmodule FormatFix do
        def format_price(cents) do
          dollars = div(cents, 100)
          cents_part = rem(cents, 100)
          "\#{dollars}.\#{cents_part:02}"
        end
      end
      """

      expected = """
      defmodule FormatFix do
        def format_price(cents) do
          dollars = div(cents, 100)
          cents_part = rem(cents, 100)
          "\#{dollars}.\#{String.pad_leading(Integer.to_string(cents_part), 2, \"0\")}"
        end
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # LEAVES ALONE — already correct code
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves correct code unchanged" do
    test "plain interpolation" do
      code = ~S'"#{variable}"'

      confirm_fix(fix(code), code)
    end

    test "function call interpolation" do
      code = ~S'"#{inspect(map)}"'

      confirm_fix(fix(code), code)
    end

    test "already fixed format" do
      code = ~S'"#{String.pad_leading(Integer.to_string(x), 2, "0")}"'

      confirm_fix(fix(code), code)
    end

    test "no interpolation" do
      code = "hello world"

      confirm_fix(fix(code), code)
    end

    test "empty string" do
      code = ~S'""'

      confirm_fix(fix(code), code)
    end

    test "map literal" do
      code = "%{key: value}"

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXPOINT — fixed output no longer flags and parses
  # ═══════════════════════════════════════════════════════════════════

  describe "fix reaches a fixpoint" do
    test "fixed output no longer flags" do
      assert analyze(fix(~S'"#{cents_part:02}"')) == []
    end

    test "fixed output is well-formed (parses)" do
      assert valid_syntax?(fix(~S'"#{cents_part:02}"'))
    end

    test "fixed module output is well-formed (parses)" do
      code = """
      defmodule FormatFix do
        def format_price(cents) do
          dollars = div(cents, 100)
          cents_part = rem(cents, 100)
          "\#{dollars}.\#{cents_part:02}"
        end
      end
      """

      assert valid_syntax?(fix(code))
    end
  end
end
