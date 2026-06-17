defmodule Credence.Pattern.PreferFunctionClausesForListPatternsCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFunctionClausesForListPatterns

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — case dispatching on a list parameter inside a guarded clause
  # ═══════════════════════════════════════════════════════════════════

  describe "flags the anti-pattern" do
    test "case with empty, single, and cons patterns" do
      assert flagged?(PreferFunctionClausesForListPatterns, """
             def my_fun(list, k) when is_list(list) and is_integer(k) and k >= 0 do
               case list do
                 [] -> 0
                 [_single] -> 0
                 [h | t] -> h + t
               end
             end
             """)
    end

    test "case with only empty and cons patterns" do
      assert flagged?(PreferFunctionClausesForListPatterns, """
             def process(list) when is_list(list) do
               case list do
                 [] -> :empty
                 [h | t] -> {:ok, h, t}
               end
             end
             """)
    end

    test "case with is_list guard and other guards" do
      assert flagged?(PreferFunctionClausesForListPatterns, """
             def calculate(list, n) when is_list(list) and is_integer(n) do
               case list do
                 [] -> 0
                 [_] -> n
                 [a, b | _] -> a + b + n
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — deliberately dropped shapes (no safe same-answer rewrite)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when there's no is_list guard" do
    test "case on a parameter without is_list guard" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def process(list) when is_integer(list) do
               case list do
                 0 -> :zero
                 n -> {:ok, n}
               end
             end
             """)
    end
  end

  describe "does not flag when case is not on the guarded parameter" do
    test "case on a different variable" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def process(list, other) when is_list(list) do
               case other do
                 [] -> :empty
                 [h | t] -> {:ok, h}
               end
             end
             """)
    end
  end

  describe "does not flag when case has fewer than 2 clauses" do
    test "single-clause case" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def process(list) when is_list(list) do
               case list do
                 _ -> :ok
               end
             end
             """)
    end
  end

  describe "does not flag when case has non-list patterns" do
    test "case with tuple patterns" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def process(list) when is_list(list) do
               case list do
                 {:ok, val} -> val
                 {:error, msg} -> msg
               end
             end
             """)
    end
  end

  describe "does not flag when case uses pin" do
    test "case with pinned variable" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def process(list, expected) when is_list(list) do
               case list do
                 ^expected -> :match
                 _ -> :no_match
               end
             end
             """)
    end
  end

  describe "does not flag when body has more than just the case" do
    test "body with pre-computation" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def process(list) when is_list(list) do
               x = length(list)
               case list do
                 [] -> 0
                 [h | t] -> h + x
               end
             end
             """)
    end
  end

  describe "does not flag when no when guard" do
    test "plain def without guard" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def process(list) do
               case list do
                 [] -> 0
                 [h | t] -> h
               end
             end
             """)
    end
  end

  describe "does not flag a non-total case" do
    # `[]` + `[_only]` leaves lists of length >= 2 unmatched: the original
    # raises CaseClauseError, function heads would raise FunctionClauseError —
    # a different answer. Only fire when the list patterns are exhaustive.
    test "empty and single-element only (no cons catch-all)" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def g(list) when is_list(list) do
               case list do
                 [] -> :empty
                 [_only] -> :one
               end
             end
             """)
    end

    test "cons catch-all only, no empty clause" do
      assert clean?(PreferFunctionClausesForListPatterns, """
             def g(list) when is_list(list) do
               case list do
                 [_x] -> :one
                 [_a, _b | _] -> :many
               end
             end
             """)
    end
  end
end
