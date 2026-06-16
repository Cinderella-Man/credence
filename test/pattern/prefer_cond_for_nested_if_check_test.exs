defmodule Credence.Pattern.PreferCondForNestedIfCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferCondForNestedIf

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags nested if/else with inner if" do
    test "basic nested if/else" do
      assert flagged?(PreferCondForNestedIf, """
             if x > 0 do
               "positive"
             else
               if x < 0 do
                 "negative"
               else
                 "zero"
               end
             end
             """)
    end

    test "inside a function" do
      assert flagged?(PreferCondForNestedIf, """
             def test(x) do
               if x > 0 do
                 "positive"
               else
                 if x < 0 do
                   "negative"
                 else
                   "zero"
                 end
               end
             end
             """)
    end

    test "inside a module" do
      assert flagged?(PreferCondForNestedIf, """
             defmodule Example do
               def test(x) do
                 if x > 0 do
                   "positive"
                 else
                   if x < 0 do
                     "negative"
                   else
                     "zero"
                   end
                 end
               end
             end
             """)
    end

    test "nested with different conditions" do
      assert flagged?(PreferCondForNestedIf, """
             if a == :ok do
               :first
             else
               if b > 10 do
                 :second
               else
                 :third
               end
             end
             """)
    end

    test "call, map and tuple bodies" do
      assert flagged?(PreferCondForNestedIf, """
             if a == :ok do
               foo(a: 1, b: 2)
             else
               if b > 10 do
                 %{a: 1, b: 2}
               else
                 {:error, reason}
               end
             end
             """)
    end

    test "flags the inner level of a three-level nesting" do
      # The outer `if a` stays (its else body contains an `if`), but the inner
      # `if b / if c` is a simple flattenable nesting and is flagged.
      assert flagged?(PreferCondForNestedIf, """
             if a do
               1
             else
               if b do
                 2
               else
                 if c do
                   3
                 else
                   4
                 end
               end
             end
             """)
    end

    test "used as expression" do
      assert flagged?(PreferCondForNestedIf, """
             result = if x > 0 do
               "positive"
             else
               if x < 0 do
                 "negative"
               else
                 "zero"
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag if without else" do
    test "simple if without else" do
      assert clean?(PreferCondForNestedIf, """
             if x > 0 do
               "positive"
             end
             """)
    end

    test "if/else without nested if" do
      assert clean?(PreferCondForNestedIf, """
             if x > 0 do
               "positive"
             else
               "non-positive"
             end
             """)
    end
  end

  describe "does not flag if/else with non-if else body" do
    test "else body is a function call" do
      assert clean?(PreferCondForNestedIf, """
             if x > 0 do
               "positive"
             else
               compute(x)
             end
             """)
    end

    test "else body is a variable" do
      assert clean?(PreferCondForNestedIf, """
             if x > 0 do
               "positive"
             else
               default
             end
             """)
    end
  end

  describe "does not flag inner if without else" do
    test "inner if has no else branch" do
      assert clean?(PreferCondForNestedIf, """
             if x > 0 do
               "positive"
             else
               if x < 0 do
                 "negative"
               end
             end
             """)
    end
  end

  # The fix reassembles each condition/body as a single `cond` clause line, so
  # the rule only fires when every condition and body is a simple, single-line
  # expression. Block-form bodies (if/case/cond/with/for/fn/receive/try) and
  # multi-line/multi-statement bodies are deliberately left alone — see the
  # corresponding "must NOT modify" cases in the fix test.

  describe "does not flag when a body is itself a block form" do
    test "an outer body contains a case expression" do
      assert clean?(PreferCondForNestedIf, """
             if x > 0 do
               case y do
                 :a -> 1
                 _ -> 2
               end
             else
               if x < 0 do
                 "negative"
               else
                 "zero"
               end
             end
             """)
    end

    test "an inner body is a multi-statement block" do
      assert clean?(PreferCondForNestedIf, """
             if x > 0 do
               "positive"
             else
               if x < 0 do
                 a = 1
                 a + 1
               else
                 "zero"
               end
             end
             """)
    end
  end

  describe "does not flag non-if constructs" do
    test "cond expression" do
      assert clean?(PreferCondForNestedIf, """
             cond do
               x > 0 -> "positive"
               x < 0 -> "negative"
               true -> "zero"
             end
             """)
    end

    test "case expression" do
      assert clean?(PreferCondForNestedIf, """
             case x do
               :ok -> :found
               _ -> :not_found
             end
             """)
    end

    test "plain function" do
      assert clean?(PreferCondForNestedIf, "def run(x), do: x * 2")
    end
  end
end
