defmodule Credence.Pattern.PreferFloatRoundFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFloatRound

  # ═══════════════════════════════════════════════════════════════════
  # BASIC REWRITE
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites the anti-pattern" do
    test "bare expression" do
      confirm_fix(fix(PreferFloatRound, ":erlang.round(x * 100) / 100"), "Float.round(x, 2)")
    end

    test "with compound inner expression" do
      confirm_fix(
        fix(PreferFloatRound, ":erlang.round(average * 100) / 100"),
        "Float.round(average, 2)"
      )
    end

    test "inside a function body" do
      input = """
      defmodule Solution do
        def round_average(grade1, grade2, grade3) do
          average = (grade1 + grade2 + grade3) / 3
          :erlang.round(average * 100) / 100
        end
      end
      """

      expected = """
      defmodule Solution do
        def round_average(grade1, grade2, grade3) do
          average = (grade1 + grade2 + grade3) / 3
          Float.round(average, 2)
        end
      end
      """

      confirm_fix(fix(PreferFloatRound, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "multiple occurrences" do
    test "fixes all occurrences" do
      input = """
      defmodule Multi do
        def round_both(a, b) do
          x = :erlang.round(a * 100) / 100
          y = :erlang.round(b * 100) / 100
          {x, y}
        end
      end
      """

      expected = """
      defmodule Multi do
        def round_both(a, b) do
          x = Float.round(a, 2)
          y = Float.round(b, 2)
          {x, y}
        end
      end
      """

      confirm_fix(fix(PreferFloatRound, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — already correct or non-matching
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch already-correct code" do
    test "Float.round(x, 2) unchanged" do
      code = "Float.round(x, 2)"

      confirm_fix(fix(PreferFloatRound, code), code)
    end

    test ":erlang.round(x) unchanged" do
      code = ":erlang.round(x)"

      confirm_fix(fix(PreferFloatRound, code), code)
    end

    test ":erlang.round(x * 100) without / 100 unchanged" do
      code = ":erlang.round(x * 100)"

      confirm_fix(fix(PreferFloatRound, code), code)
    end

    test "other arithmetic unchanged" do
      code = "x * 100 / 100"

      confirm_fix(fix(PreferFloatRound, code), code)
    end
  end
end
