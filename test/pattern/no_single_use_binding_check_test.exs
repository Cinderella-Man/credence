defmodule Credence.Pattern.NoSingleUseBindingCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoSingleUseBinding

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoSingleUseBinding.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD FLAG — single-use binding in comparison expression
  # ═══════════════════════════════════════════════════════════════════

  describe "flags single-use binding in comparison" do
    test "equality comparison after GCD" do
      assert flagged?("""
             def run(a, b) do
               gcd = Integer.gcd(a, b)
               gcd == 1
             end
             """)
    end

    test "greater-than comparison" do
      assert flagged?("""
             def run(x) do
               val = compute(x)
               val > 0
             end
             """)
    end

    test "not-equal comparison" do
      assert flagged?("""
             def run(x) do
               result = process(x)
               result != nil
             end
             """)
    end

    test "less-than-or-equal comparison" do
      assert flagged?("""
             def run(x) do
               len = String.length(x)
               len <= 100
             end
             """)
    end

    test "strict equality comparison" do
      assert flagged?("""
             def run(x) do
               type = typeof(x)
               type === :integer
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD FLAG — single-use binding in boolean expression
  # ═══════════════════════════════════════════════════════════════════

  describe "flags single-use binding in boolean expression" do
    test "boolean and with one use" do
      assert flagged?("""
             def run(x) do
               val = compute(x)
               val > 0 and other_check(x)
             end
             """)
    end

    test "boolean or with one use" do
      assert flagged?("""
             def run(x) do
               val = compute(x)
               val == :ok or fallback(x)
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD FLAG — simple variable alias used once
  # ═══════════════════════════════════════════════════════════════════

  describe "flags simple variable alias used once" do
    test "alias used in function call" do
      assert flagged?("""
             def run(list, char) do
               target = char
               do_count(list, target, 0, 0)
             end
             """)
    end

    test "alias used in arithmetic" do
      assert flagged?("""
             def run(x) do
               y = x
               y + 1
             end
             """)
    end

    test "alias used in pipe" do
      assert flagged?("""
             def run(list) do
               data = list
               data |> Enum.map(&process/1)
             end
             """)
    end

    test "alias used in string interpolation" do
      assert flagged?("""
             def run(name) do
               label = name
               "Hello, \#{label}"
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — non-operator expressions (RHS is not a simple var)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when next expression is not comparison/boolean and RHS is not a simple var" do
    test "function call argument" do
      assert clean?("""
             def run(list) do
               count = Enum.count(list)
               IO.puts(count)
             end
             """)
    end

    test "arithmetic expression" do
      assert clean?("""
             def run(a, b) do
               sum = a + b
               sum * 2
             end
             """)
    end

    test "pipe expression" do
      assert clean?("""
             def run(list) do
               result = Enum.map(list, &process/1)
               result |> Enum.filter(&valid?/1)
             end
             """)
    end

    test "string interpolation" do
      assert clean?("""
             def run(x) do
               name = get_name(x)
               "Hello, \#{name}"
             end
             """)
    end

    test "list construction" do
      assert clean?("""
             def run(x) do
               val = compute(x)
               [val]
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — variable used multiple times
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when variable is used multiple times" do
    test "used twice in boolean and" do
      assert clean?("""
             def run(a, b) do
               gcd = Integer.gcd(a, b)
               gcd > 0 and gcd < 10
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — variable is the entire next expression
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when variable is the entire next expression" do
    test "assign and return same variable" do
      assert clean?("""
             def run(a, b) do
               gcd = Integer.gcd(a, b)
               gcd
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — control-flow expressions
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when next expression is control flow" do
    test "if expression" do
      assert clean?("""
             def run(x) do
               result = compute(x)
               if result > 0, do: :positive, else: :non_positive
             end
             """)
    end

    test "case expression" do
      assert clean?("""
             def run(x) do
               result = compute(x)
               case result do
                 :ok -> :success
                 :error -> :failure
               end
             end
             """)
    end

    test "cond expression" do
      assert clean?("""
             def run(x) do
               result = compute(x)
               cond do
                 result > 0 -> :positive
                 result < 0 -> :negative
                 true -> :zero
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — non-simple assignments
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag pattern match assignments" do
    test "tuple pattern" do
      assert clean?("""
             def run(input) do
               {a, b} = process(input)
               a + b
             end
             """)
    end
  end

  describe "does not flag underscore assignments" do
    test "_ = expr then use" do
      assert clean?("""
             def run(x) do
               _ = side_effect(x)
               :ok
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD NOT FLAG — edge cases
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag single-statement blocks" do
    test "no assignment" do
      assert clean?("""
             def run(x) do
               compute(x)
             end
             """)
    end
  end

  describe "does not flag already-optimal code" do
    test "direct comparison without intermediate binding" do
      assert clean?("""
             def run(a, b) do
               Integer.gcd(a, b) == 1
             end
             """)
    end

    test "variable used multiple times in next expression" do
      assert clean?("""
             def run(list) do
               sorted = Enum.sort(list)
               Enum.at(sorted, 0) + Enum.at(sorted, -1)
             end
             """)
    end
  end
end
