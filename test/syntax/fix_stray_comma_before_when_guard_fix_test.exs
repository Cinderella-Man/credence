defmodule Credence.Syntax.FixStrayCommaBeforeWhenGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixStrayCommaBeforeWhenGuard

  defp analyze(code), do: FixStrayCommaBeforeWhenGuard.analyze(code)
  defp fix(code), do: FixStrayCommaBeforeWhenGuard.fix(code)

  # ═══════════════════════════════════════════════════════════════════
  # FIXES — stray comma before when guard
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes stray comma before when guard" do
    test "comma and when on same line" do
      input = "def positive?(x), when x > 0, do: true"
      expected = "def positive?(x) when x > 0, do: true"

      confirm_fix(fix(input), expected)
    end

    test "comma on one line, when on next line" do
      input = """
      defmodule Example do
        def positive?(x),
          when x > 0, do: true
        def positive?(_), do: false
      end
      """

      expected = """
      defmodule Example do
        def positive?(x) when x > 0, do: true
        def positive?(_), do: false
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "multiple clauses with stray comma" do
      input = """
      defmodule Example do
        def positive?(x),
          when x > 0, do: true
        def positive?(_), do: false
        def zero?(x),
          when x == 0, do: true
        def zero?(_), do: false
      end
      """

      expected = """
      defmodule Example do
        def positive?(x) when x > 0, do: true
        def positive?(_), do: false
        def zero?(x) when x == 0, do: true
        def zero?(_), do: false
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ROUND-TRIP — fixed output no longer flags
  # ═══════════════════════════════════════════════════════════════════

  describe "round-trip" do
    test "fixed output no longer flags" do
      input = """
      defmodule Example do
        def positive?(x),
          when x > 0, do: true
        def positive?(_), do: false
      end
      """

      assert analyze(fix(input)) == []
    end

    test "single-line fixed output no longer flags" do
      input = "def positive?(x), when x > 0, do: true"

      assert analyze(fix(input)) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # VALID SYNTAX — fixed output parses
  # ═══════════════════════════════════════════════════════════════════

  describe "fix output is well-formed" do
    test "single-line fix parses" do
      input = "def positive?(x), when x > 0, do: true"

      assert valid_syntax?(fix(input))
    end

    test "multi-line fix parses" do
      input = """
      defmodule Example do
        def positive?(x),
          when x > 0, do: true
        def positive?(_), do: false
      end
      """

      assert valid_syntax?(fix(input))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — already correct code
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch already correct code" do
    test "function guard without stray comma" do
      code = "def positive?(x) when x > 0, do: true"

      confirm_fix(fix(code), code)
    end

    test "function without guard" do
      code = "def positive?(_), do: false"

      confirm_fix(fix(code), code)
    end

    test "case clause guard" do
      code = """
      case x do
        n when n > 0 -> :positive
        _ -> :zero
      end
      """

      confirm_fix(fix(code), code)
    end

    test "empty string" do
      confirm_fix(fix(""), "")
    end
  end
end
