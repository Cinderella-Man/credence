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
  # POSITIVE — single-parameter, total `case` on that parameter
  # ═══════════════════════════════════════════════════════════════════

  describe "flags single-param case dispatch" do
    test "literal + variable catch-all" do
      assert flagged?("""
             def run(x) do
               case x do
                 0 -> :zero
                 n -> {:ok, n}
               end
             end
             """)
    end

    test "list patterns with `_` catch-all (pick_coins style)" do
      assert flagged?("""
             def pick_coins(coins) do
               case coins do
                 [] -> 0
                 [first] -> first
                 [first, second] -> max(first, second)
                 _ -> do_pick_coins(coins, 0, 0)
               end
             end
             """)
    end

    test "map patterns with `_` catch-all" do
      assert flagged?("""
             def handle(msg) do
               case msg do
                 %{type: :ping} -> :pong
                 %{type: :data, payload: p} -> process(p)
                 _ -> :unknown
               end
             end
             """)
    end

    test "defp with a clause guard and `_` catch-all" do
      assert flagged?("""
             defp classify(x) do
               case x do
                 0 -> :zero
                 n when n > 0 -> :positive
                 _ -> :negative
               end
             end
             """)
    end

    test "catch-all is a bound variable (not `_`)" do
      assert flagged?("""
             def last(list) do
               case list do
                 [] -> nil
                 list -> List.last(list)
               end
             end
             """)
    end

    test "one-liner def body that is a case" do
      assert flagged?("""
             def run(x), do: (case x do
               0 -> :zero
               _ -> :other
             end)
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — deliberately dropped shapes (no safe same-answer rewrite)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag multi-parameter / tuple dispatch (out of scope)" do
    test "case on a tuple of two params (gcd style)" do
      assert clean?("""
             def gcd(x, y) do
               case {x, y} do
                 {0, y} -> y
                 {x, 0} -> x
                 _ -> gcd(y, rem(x, y))
               end
             end
             """)
    end

    test "case on a tuple of three params" do
      assert clean?("""
             def merge(a, b, c) do
               case {a, b, c} do
                 {nil, nil, nil} -> :empty
                 {x, y, z} -> {x, y, z}
               end
             end
             """)
    end

    test "case on a tuple with reversed param order" do
      assert clean?("""
             def swap(x, y) do
               case {y, x} do
                 {0, 0} -> :zero
                 {a, b} -> {a, b}
               end
             end
             """)
    end
  end

  describe "does not flag a non-total case (exception type would change)" do
    test "no catch-all clause" do
      assert clean?("""
             def f(x) do
               case x do
                 0 -> :a
                 1 -> :b
               end
             end
             """)
    end

    test "the only would-be catch-all is itself guarded" do
      assert clean?("""
             def f(x) do
               case x do
                 0 -> :a
                 n when n > 0 -> :b
               end
             end
             """)
    end
  end

  describe "does not flag a function-head guard" do
    test "def with a `when` guard on the head" do
      assert clean?("""
             def f(x) when is_integer(x) do
               case x do
                 0 -> :zero
                 _ -> :other
               end
             end
             """)
    end
  end

  describe "does not flag a pinned pattern" do
    test "`^` pin cannot become an unbound function-head pattern" do
      assert clean?("""
             def f(x) do
               case x do
                 ^x -> :same
                 _ -> :other
               end
             end
             """)
    end
  end

  describe "does not flag when the body is more than just the case" do
    test "single param but with pre-computation" do
      assert clean?("""
             def run(x) do
               y = x + 1
               case x do
                 0 -> y
                 _ -> {:y, y}
               end
             end
             """)
    end

    test "case with a trailing rescue clause" do
      assert clean?("""
             def f(x) do
               case x do
                 0 -> :a
                 _ -> :b
               end
             rescue
               _ -> :error
             end
             """)
    end
  end

  describe "does not flag case on non-parameter values" do
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
                 _ -> :failed
               end
             end
             """)
    end
  end

  describe "does not flag fewer than two clauses" do
    test "single-clause case" do
      assert clean?("""
             def f(x) do
               case x do
                 _ -> :always
               end
             end
             """)
    end
  end

  describe "does not flag multi-clause functions" do
    test "already idiomatic" do
      assert clean?("""
             def gcd(0, y), do: y
             def gcd(x, 0), do: x
             def gcd(x, y), do: gcd(y, rem(x, y))
             """)
    end
  end

  describe "does not flag non-function constructs" do
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
