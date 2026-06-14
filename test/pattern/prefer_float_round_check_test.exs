defmodule Credence.Pattern.PreferFloatRoundCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFloatRound

  # ═══════════════════════════════════════════════════════════════════
  # FLAGGED — the anti-pattern
  # ═══════════════════════════════════════════════════════════════════

  describe "flags the anti-pattern" do
    test "flags :erlang.round(x * 100) / 100 with bare variable" do
      assert flagged?(PreferFloatRound, ":erlang.round(x * 100) / 100")
    end

    test "flags with compound expression" do
      assert flagged?(PreferFloatRound, ":erlang.round(average * 100) / 100")
    end

    test "flags inside a function body" do
      assert flagged?(PreferFloatRound, """
             defmodule Solution do
               def round_average(grade1, grade2, grade3) do
                 average = (grade1 + grade2 + grade3) / 3
                 :erlang.round(average * 100) / 100
               end
             end
             """)
    end

    test "flags multiple occurrences" do
      code = """
      defmodule Multi do
        def round_both(a, b) do
          x = :erlang.round(a * 100) / 100
          y = :erlang.round(b * 100) / 100
          {x, y}
        end
      end
      """

      assert length(check(PreferFloatRound, code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MUST NOT FLAG — already correct
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves good code alone" do
    test "Float.round(x, 2) is not flagged" do
      assert clean?(PreferFloatRound, "Float.round(x, 2)")
    end

    test ":erlang.round without the * 100 / 100 pattern" do
      assert clean?(PreferFloatRound, ":erlang.round(x)")
    end

    test ":erlang.round(x * 100) without / 100" do
      assert clean?(PreferFloatRound, ":erlang.round(x * 100)")
    end

    test ":erlang.round(x * 100) / 10 (wrong divisor)" do
      assert clean?(PreferFloatRound, ":erlang.round(x * 100) / 10")
    end

    test ":erlang.round(x * 10) / 10 (wrong multiplier)" do
      assert clean?(PreferFloatRound, ":erlang.round(x * 10) / 10")
    end

    test "plain arithmetic" do
      assert clean?(PreferFloatRound, "x * 100")
    end
  end
end
