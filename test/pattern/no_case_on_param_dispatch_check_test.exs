defmodule Credence.Pattern.NoCaseOnParamDispatchCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCaseOnParamDispatch

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaseOnParamDispatch.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case on tuple of function params" do
    test "gcd style: case {x, y} with literal and catch-all arms" do
      assert flagged?("""
             def gcd(x, y) do
               case {x, y} do
                 {0, y} -> y
                 {x, 0} -> x
                 _ -> gcd(y, rem(x, y))
               end
             end
             """)
    end

    test "case on two params with when guard on function" do
      assert flagged?("""
             def classify(x, y) when is_integer(x) do
               case {x, y} do
                 {0, 0} -> :zero
                 {_, _} -> :other
               end
             end
             """)
    end

    test "case on three params" do
      assert flagged?("""
             def merge(a, b, c) do
               case {a, b, c} do
                 {nil, nil, nil} -> :empty
                 {x, y, z} -> {x, y, z}
               end
             end
             """)
    end

    test "defp variant" do
      assert flagged?("""
             defp do_run(x, y) do
               case {x, y} do
                 {0, y} -> y
                 {x, 0} -> x
                 _ -> do_run(y, rem(x, y))
               end
             end
             """)
    end

    test "case with reversed param order in tuple" do
      assert flagged?("""
             def swap(x, y) do
               case {y, x} do
                 {0, 0} -> :zero
                 {a, b} -> {a, b}
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag multi-clause functions" do
    test "multi-clause function (already idiomatic)" do
      assert clean?("""
             def gcd(0, y), do: y
             def gcd(x, 0), do: x
             def gcd(x, y), do: gcd(y, rem(x, y))
             """)
    end
  end

  describe "does not flag case on non-param values" do
    test "case on a computed value" do
      assert clean?("""
             def run(x, y) do
               result = x + y
               case result do
                 0 -> :zero
                 n -> {:ok, n}
               end
             end
             """)
    end

    test "case on a function call" do
      assert clean?("""
             def run(x) do
               case do_something(x) do
                 :ok -> :done
                 :error -> :failed
               end
             end
             """)
    end

    test "case on a single param (not a tuple)" do
      assert clean?("""
             def run(x) do
               case x do
                 0 -> :zero
                 n -> {:ok, n}
               end
             end
             """)
    end
  end

  describe "does not flag functions with additional logic" do
    test "case on params but with pre-computation" do
      assert clean?("""
             def run(x, y) do
               z = x + y
               case {x, y} do
                 {0, 0} -> z
                 {a, b} -> a + b + z
               end
             end
             """)
    end
  end

  describe "does not flag case on a tuple with non-param elements" do
    test "tuple includes a computed value" do
      assert clean?("""
             def run(x, y) do
               case {x, y, x + y} do
                 {0, 0, _} -> :zero
                 {_, _, s} -> {:sum, s}
               end
             end
             """)
    end
  end

  describe "does non-flag non-function constructs" do
    test "case in a module body (not a function)" do
      assert clean?("""
             defmodule M do
               x = 1
               case {x} do
                 {0} -> :zero
                 _ -> :other
               end
             end
             """)
    end
  end
end
