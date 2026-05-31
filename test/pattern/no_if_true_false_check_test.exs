defmodule Credence.Pattern.NoIfTrueFalseCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoIfTrueFalse

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoIfTrueFalse.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags if...do true...else false" do
    test "basic block form" do
      assert flagged?("""
             def check(x) do
               if x > 0 do
                 true
               else
                 false
               end
             end
             """)
    end

    test "with function call condition" do
      assert flagged?("""
             def check(list) do
               if Enum.all?(list, &valid?/1) do
                 true
               else
                 false
               end
             end
             """)
    end

    test "with complex boolean condition" do
      assert flagged?("""
             def check(parts) do
               if match?([_, _, _, _], parts) and Enum.all?(parts, &valid_octet?/1) do
                 true
               else
                 false
               end
             end
             """)
    end

    test "inline form" do
      assert flagged?("""
             def check(x) do
               if x > 0, do: true, else: false
             end
             """)
    end

    test "reversed boolean branches (false/true) — NOT flagged, would need negation" do
      assert clean?("""
             def check(x) do
               if x > 0 do
                 false
               else
                 true
               end
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
             defmodule Validator do
               def valid?(items) do
                 if length(items) == 4 do
                   true
                 else
                   false
                 end
               end
             end
             """)
    end

    test "used as expression assignment" do
      assert flagged?("""
             def run(x) do
               result = if x > 0 do
                 true
               else
                 false
               end
               result
             end
             """)
    end

    test "nested — flags both" do
      code = """
      def run(x, y) do
        a = if x > 0 do
          true
        else
          false
        end
        b = if y > 0 do
          true
        else
          false
        end
        {a, b}
      end
      """

      assert length(check(code)) == 2
    end

    test "comparison in do body with else false" do
      assert flagged?("""
             def check(x, y) do
               if x > 0 do
                 y == 1
               else
                 false
               end
             end
             """)
    end

    test "boolean operator in do body with else false" do
      assert flagged?("""
             def check(x, a, b) do
               if x > 0 do
                 a and b
               else
                 false
               end
             end
             """)
    end

    test "not expression in do body with else false" do
      assert flagged?("""
             def check(x, y) do
               if x > 0 do
                 not y
               else
                 false
               end
             end
             """)
    end

    test "inline comparison form" do
      assert flagged?("""
             def check(x, y) do
               if x > 0, do: y == 1, else: false
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag if with non-boolean returns" do
    test "if with non-boolean values" do
      assert clean?("""
             def run(x) do
               if x > 0 do
                 :positive
               else
                 :negative
               end
             end
             """)
    end

    test "if with computed values" do
      assert clean?("""
             def run(x) do
               if x > 0 do
                 x * 2
               else
                 0
               end
             end
             """)
    end

    test "if with string returns" do
      assert clean?("""
             def run(x) do
               if x > 0 do
                 "yes"
               else
                 "no"
               end
             end
             """)
    end

    test "comparison in do body but non-false else" do
      assert clean?("""
             def run(x, y) do
               if x > 0 do
                 y == 1
               else
                 true
               end
             end
             """)
    end

    test "function call in do body with else false — not flagged (may not return bool)" do
      assert clean?("""
             def run(x) do
               if x > 0 do
                 some_check(x)
               else
                 false
               end
             end
             """)
    end

    test "arithmetic in do body with else false — not flagged" do
      assert clean?("""
             def run(x, y) do
               if x > 0 do
                 y + 1
               else
                 false
               end
             end
             """)
    end
  end

  describe "does not flag if without else" do
    test "bare if block" do
      assert clean?("""
             def run(x) do
               if x > 0 do
                 IO.puts("positive")
               end
             end
             """)
    end
  end

  describe "does not flag code without if" do
    test "plain function" do
      assert clean?("""
             defmodule M do
               def run(x), do: x * 2
             end
             """)
    end

    test "case expression" do
      assert clean?("""
             def run(x) do
               case x do
                 :a -> 1
                 :b -> 2
               end
             end
             """)
    end
  end
end
