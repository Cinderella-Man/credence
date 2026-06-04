defmodule Credence.Pattern.NoCaseTupleGuardDispatchCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCaseTupleGuardDispatch

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaseTupleGuardDispatch.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case on tuple with guard-only dispatch" do
    test "two-tuple with guards and wildcard catch-all" do
      assert flagged?("""
             def run(e1, e2) do
               case {e1, e2} do
                 {e1, e2} when e1 < e2 -> :left
                 {e1, e2} when e1 > e2 -> :right
                 _ -> :equal
               end
             end
             """)
    end

    test "two-tuple with explicit tuple catch-all" do
      assert flagged?("""
             def run(e1, e2) do
               case {e1, e2} do
                 {e1, e2} when e1 < e2 -> :left
                 {e1, e2} when e1 > e2 -> :right
                 {e1, e2} -> :equal
               end
             end
             """)
    end

    test "three-tuple with guards" do
      assert flagged?("""
             def run(a, b, c) do
               case {a, b, c} do
                 {a, b, c} when a < b and b < c -> :ascending
                 {a, b, c} when a > b and b > c -> :descending
                 {a, b, c} -> :other
               end
             end
             """)
    end

    test "complex bodies" do
      assert flagged?("""
             def run(e1, e2) do
               case {e1, e2} do
                 {e1, e2} when e1 < e2 ->
                   x = e1 + e2
                   process(x)
                 {e1, e2} when e1 > e2 ->
                   y = e1 - e2
                   process(y)
                 _ ->
                   :equal
               end
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
             defmodule IntervalMerge do
               def merge({s1, e1}, {s2, e2}) do
                 case {s1, e1, s2, e2} do
                   {s1, e1, s2, e2} when e1 < s2 -> [{s1, e1}]
                   {s1, e1, s2, e2} when e2 < s1 -> [{s2, e2}]
                   {s1, e1, s2, e2} -> [{min(s1, s2), max(e1, e2)}]
                 end
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag case with structural pattern matching" do
    test "pattern matches on atom literals" do
      assert clean?("""
             def run(x) do
               case x do
                 :ok -> :success
                 :error -> :failure
               end
             end
             """)
    end

    test "pattern matches on tuple structure" do
      assert clean?("""
             def run(x) do
               case x do
                 {:ok, val} -> val
                 {:error, _} -> :default
               end
             end
             """)
    end

    test "tuple patterns with different variable names" do
      assert clean?("""
             def run(e1, e2) do
               case {e1, e2} do
                 {a, b} when a < b -> :left
                 {c, d} when c > d -> :right
                 _ -> :equal
               end
             end
             """)
    end
  end

  describe "does not flag case without guards" do
    test "all clauses have structural patterns" do
      assert clean?("""
             def run(x) do
               case x do
                 {0, y} -> y
                 {x, 0} -> x
                 _ -> x + y
               end
             end
             """)
    end
  end

  describe "does not flag case on non-tuple" do
    test "case on variable" do
      assert clean?("""
             def run(x) do
               case x do
                 y when y > 0 -> :positive
                 _ -> :non_positive
               end
             end
             """)
    end

    test "case on function call" do
      assert clean?("""
             def run(list) do
               case length(list) do
                 n when n > 0 -> :non_empty
                 _ -> :empty
               end
             end
             """)
    end
  end

  describe "does not flag single-clause case" do
    test "one clause with guard" do
      assert clean?("""
             def run(e1, e2) do
               case {e1, e2} do
                 {e1, e2} when e1 < e2 -> :less
               end
             end
             """)
    end
  end

  describe "does not flag non-case constructs" do
    test "cond with guards" do
      assert clean?("""
             def run(e1, e2) do
               cond do
                 e1 < e2 -> :less
                 e1 > e2 -> :greater
                 true -> :equal
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — deliberately skipped unsafe cases (locking in safety)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when there is no guardless catch-all" do
    # case with no catch-all raises CaseClauseError on a non-matching
    # input; the cond would raise CondClauseError — a different value.
    test "two guarded clauses, no catch-all" do
      assert clean?("""
             def run(a, b) do
               case {a, b} do
                 {a, b} when a < b -> :less
                 {a, b} when a > b -> :greater
               end
             end
             """)
    end

    test "all clauses guarded, no catch-all (three-tuple)" do
      assert clean?("""
             def run(a, b, c) do
               case {a, b, c} do
                 {a, b, c} when a < b -> :x
                 {a, b, c} when b < c -> :y
               end
             end
             """)
    end
  end

  describe "does not flag guards that can raise" do
    # `hd(a)` in a guard treats a raised error as a failed clause; as a
    # cond condition it would propagate the error instead.
    test "guard calls a function that can raise" do
      assert clean?("""
             def run(a, b) do
               case {a, b} do
                 {a, b} when hd(a) > b -> :left
                 _ -> :other
               end
             end
             """)
    end

    test "guard uses arithmetic (raises on non-numbers)" do
      assert clean?("""
             def run(a, b) do
               case {a, b} do
                 {a, b} when a + 1 > b -> :left
                 _ -> :other
               end
             end
             """)
    end

    test "guard uses a type check that can raise (elem)" do
      assert clean?("""
             def run(a, b) do
               case {a, b} do
                 {a, b} when elem(a, 0) > b -> :left
                 _ -> :other
               end
             end
             """)
    end
  end

  describe "does not flag bare-variable truthiness guards" do
    # `when a` succeeds only when a === true; `cond a ->` succeeds on any
    # truthy value — a different selection.
    test "guard is a bare variable" do
      assert clean?("""
             def run(a, b) do
               case {a, b} do
                 {a, b} when a -> :left
                 _ -> :other
               end
             end
             """)
    end
  end
end
