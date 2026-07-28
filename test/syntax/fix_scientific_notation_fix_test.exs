defmodule Credence.Syntax.FixScientificNotationFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixScientificNotation

  defp fix(code) do
    FixScientificNotation.fix(code)
  end

  describe "fixes bare integer scientific notation" do
    test "1e-10 → 1.0e-10" do
      confirm_fix(fix("x = 1e-10"), "x = 1.0e-10")
    end

    test "1e10 → 1.0e10" do
      confirm_fix(fix("x = 1e10"), "x = 1.0e10")
    end

    test "1e+10 → 1.0e+10" do
      confirm_fix(fix("x = 1e+10"), "x = 1.0e+10")
    end

    test "100e3 → 100.0e3" do
      confirm_fix(fix("x = 100e3"), "x = 100.0e3")
    end

    test "5e-3 → 5.0e-3" do
      confirm_fix(fix("x = 5e-3"), "x = 5.0e-3")
    end

    test "uppercase E normalized to lowercase" do
      confirm_fix(fix("x = 1E-10"), "x = 1.0e-10")
    end

    test "inside assert_in_delta" do
      confirm_fix(
        fix("assert_in_delta result, 0.5, 1e-10"),
        "assert_in_delta result, 0.5, 1.0e-10"
      )
    end

    test "multiple on same line" do
      confirm_fix(fix("assert_in_delta a, 1e-5, 1e-10"), "assert_in_delta a, 1.0e-5, 1.0e-10")
    end
  end

  describe "leaves valid notation unchanged" do
    test "1.0e-10" do
      confirm_fix(fix("x = 1.0e-10"), "x = 1.0e-10")
    end

    test "1.5e10" do
      confirm_fix(fix("x = 1.5e10"), "x = 1.5e10")
    end

    test "2.0e+3" do
      confirm_fix(fix("x = 2.0e+3"), "x = 2.0e+3")
    end
  end

  describe "leaves decimal-with-exponent strings unchanged" do
    test "123.456e7 in doctest" do
      code = ~S'iex> Solution.float?("123.456e7")'

      confirm_fix(fix(code), code)
    end

    test "123.456e+7 in doctest" do
      code = ~S'iex> Solution.float?("123.456e+7")'

      confirm_fix(fix(code), code)
    end

    test "123.456E7 in doctest" do
      code = ~S'iex> Solution.float?("123.456E7")'

      confirm_fix(fix(code), code)
    end

    test "0.5e-10 in assert_in_delta" do
      code = "assert_in_delta result, 0.5e-10, 0.001"

      confirm_fix(fix(code), code)
    end
  end

  describe "leaves non-numeric content unchanged" do
    test "comments" do
      code = "# tolerance is 1e-10"

      confirm_fix(fix(code), code)
    end

    test "plain integers" do
      code = "x = 100"

      confirm_fix(fix(code), code)
    end

    test "regular code" do
      code = "Enum.map(list, &to_string/1)"

      confirm_fix(fix(code), code)
    end
  end

  describe "fix reaches a fixpoint" do
    test "fixed output no longer flags" do
      assert FixScientificNotation.analyze(fix("x = 1e-10")) == []
    end

    test "fix output is well-formed (parses)" do
      assert valid_syntax?(fix("x = 1e-10"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — an exponent inside a string is prose, not a number
  #
  # Every case below shipped corrupted. The outputs parsed AND compiled,
  # so nothing downstream noticed the program had started printing
  # something the author never wrote. The whole-line `#` guard this rule
  # used to carry caught only the pure-comment case below; the other six
  # were live.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — string literals are not code" do
    test "leaves an exponent inside a string alone" do
      code = ~S'IO.puts("version 1e5 build")'

      confirm_fix(fix(code), code)
    end

    test "leaves the string alone while still fixing real code on the same line" do
      confirm_fix(
        fix(~S'IO.puts("build 1e5"); x = 1e-10'),
        ~S'IO.puts("build 1e5"); x = 1.0e-10'
      )
    end

    test "fixes inside interpolation — that IS code" do
      confirm_fix(fix(~S'IO.puts("#{1e5}")'), ~S'IO.puts("#{1.0e5}")')
    end

    test "leaves an uppercase sigil alone — it does not interpolate" do
      code = ~S'IO.puts(~S(raw 1e5))'

      confirm_fix(fix(code), code)
    end

    test "leaves a charlist alone" do
      code = ~S'x = ~c"tolerance 1e-10"'

      confirm_fix(fix(code), code)
    end

    test "leaves a heredoc body alone" do
      code = ~S'''
      @moduledoc """
      tolerance is 1e-10
      """
      '''

      confirm_fix(fix(code), code)
    end

    test "leaves a trailing comment alone while fixing the code before it" do
      confirm_fix(fix("x = 1e5  # bump to 1e9 later"), "x = 1.0e5  # bump to 1e9 later")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # END-TO-END through the syntax phase
  # ═══════════════════════════════════════════════════════════════════

  describe "integration through Credence.Syntax" do
    test "repairs the exponent without touching the version string" do
      source = """
      defmodule SciNotationInteg do
        def render do
          IO.puts("version 1e5 build")
          assert_in_delta 0.5, 0.5, 1e-10
        end
      end
      """

      expected = """
      defmodule SciNotationInteg do
        def render do
          IO.puts("version 1e5 build")
          assert_in_delta 0.5, 0.5, 1.0e-10
        end
      end
      """

      fixed = Credence.Syntax.fix(source)
      confirm_fix(fixed, expected)
      assert valid_syntax?(fixed)
    end
  end
end
