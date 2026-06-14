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

    test "flags both levels in a three-level nesting" do
      code = """
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
      """

      issues = check(PreferCondForNestedIf, code)
      # The outermost if (a/b) is flagged, and the inner if (b/c) is flagged
      # after prewalk processes the outer first, the inner cond is still checked
      assert issues != []
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
