defmodule Credence.Pattern.NoIfSubtractionForMaxCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoIfSubtractionForMax

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoIfSubtractionForMax.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags if a > b, do: a - b, else: 0" do
    test "basic inline form" do
      assert flagged?("""
             def run(x, y) do
               if x > y, do: x - y, else: 0
             end
             """)
    end

    test "basic >= form" do
      assert flagged?("""
             def run(x, y) do
               if x >= y, do: x - y, else: 0
             end
             """)
    end

    test "block form" do
      assert flagged?("""
             def run(x, y) do
               if x > y do
                 x - y
               else
                 0
               end
             end
             """)
    end

    test "used as expression in assignment" do
      assert flagged?("""
             def run(x, y) do
               water = if x > y, do: x - y, else: 0
               water
             end
             """)
    end

    test "complex variable names" do
      assert flagged?("""
             def run(new_max_left, left_height) do
               water = if new_max_left > left_height, do: new_max_left - left_height, else: 0
               water
             end
             """)
    end

    test "nested inside if block" do
      assert flagged?("""
             def run(x, y, a, b) do
               if x > y do
                 val = if a > b, do: a - b, else: 0
                 val
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when else is not 0" do
    test "else is 1" do
      assert clean?("""
             def run(x, y) do
               if x > y, do: x - y, else: 1
             end
             """)
    end

    test "else is -1" do
      assert clean?("""
             def run(x, y) do
               if x > y, do: x - y, else: -1
             end
             """)
    end
  end

  describe "does not flag when subtraction operands don't match condition" do
    test "different left operand" do
      assert clean?("""
             def run(x, y, z) do
               if x > y, do: z - y, else: 0
             end
             """)
    end

    test "different right operand" do
      assert clean?("""
             def run(x, y, z) do
               if x > y, do: x - z, else: 0
             end
             """)
    end

    test "swapped operands" do
      assert clean?("""
             def run(x, y) do
               if x > y, do: y - x, else: 0
             end
             """)
    end
  end

  describe "does not flag when not a subtraction" do
    test "addition" do
      assert clean?("""
             def run(x, y) do
               if x > y, do: x + y, else: 0
             end
             """)
    end

    test "multiplication" do
      assert clean?("""
             def run(x, y) do
               if x > y, do: x * y, else: 0
             end
             """)
    end
  end

  describe "does not flag wrong comparison operators" do
    test "less-than comparison" do
      assert clean?("""
             def run(x, y) do
               if x < y, do: x - y, else: 0
             end
             """)
    end

    test "equality comparison" do
      assert clean?("""
             def run(x, y) do
               if x == y, do: x - y, else: 0
             end
             """)
    end
  end

  describe "does not flag non-if constructs" do
    test "cond" do
      assert clean?("""
             def run(x, y) do
               cond do
                 x > y -> x - y
                 true -> 0
               end
             end
             """)
    end
  end

  describe "does not flag max already used" do
    test "max(0, x - y)" do
      assert clean?("""
             def run(x, y) do
               max(0, x - y)
             end
             """)
    end
  end
end
