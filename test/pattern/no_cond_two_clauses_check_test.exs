defmodule Credence.Pattern.NoCondTwoClausesCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoCondTwoClauses.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags cond with exactly 2 clauses where second is true" do
    test "basic case" do
      assert flagged?("""
             def run(x) do
               cond do
                 x > 0 -> :positive
                 true -> :non_positive
               end
             end
             """)
    end

    test "complex first guard" do
      assert flagged?("""
             def run(x, y) do
               cond do
                 x > 0 and y > 0 -> :both_positive
                 true -> :not_both
               end
             end
             """)
    end

    test "function call as first guard" do
      assert flagged?("""
             def run(list) do
               cond do
                 Enum.empty?(list) -> :empty
                 true -> hd(list)
               end
             end
             """)
    end

    test "multi-line bodies" do
      assert flagged?("""
             def run(low, high, target) do
               cond do
                 low > high ->
                   false
                 true ->
                   mid = div(low + high, 2)
                   search(mid, target)
               end
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
             defmodule Search do
               def binary_search(low, high) do
                 cond do
                   low > high -> false
                   true -> :continue
                 end
               end
             end
             """)
    end

    test "used as expression" do
      assert flagged?("""
             def run(x) do
               result = cond do
                 x > 0 -> :positive
                 true -> :non_positive
               end
               result
             end
             """)
    end

    test "nested — both flagged" do
      code = """
      def run(x, y) do
        cond do
          x > 0 ->
            cond do
              y > 0 -> :both
              true -> :only_x
            end
          true -> :neither
        end
      end
      """

      assert length(check(code)) == 2
    end

    test "inside other constructs" do
      assert flagged?("""
             def run(x) do
               case x do
                 {:ok, val} ->
                   cond do
                     val > 100 -> :high
                     true -> :low
                   end
                 _ -> :error
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag cond with 3+ clauses" do
    test "three clauses with true catch-all" do
      assert clean?("""
             def run(x) do
               cond do
                 x > 0 -> :positive
                 x == 0 -> :zero
                 true -> :negative
               end
             end
             """)
    end

    test "four clauses" do
      assert clean?("""
             def run(x) do
               cond do
                 x > 10 -> :high
                 x > 0 -> :low_positive
                 x == 0 -> :zero
                 true -> :negative
               end
             end
             """)
    end
  end

  describe "does not flag cond with 2 clauses where second is not true" do
    test "both clauses have real guards" do
      assert clean?("""
             def run(x) do
               cond do
                 x > 0 -> :positive
                 x <= 0 -> :non_positive
               end
             end
             """)
    end

    test "second guard is a function call" do
      assert clean?("""
             def run(x) do
               cond do
                 x > 0 -> :positive
                 is_nil(x) -> :nil_value
               end
             end
             """)
    end
  end

  describe "does not flag cond with 1 clause" do
    test "single clause" do
      assert clean?("""
             def run(x) do
               cond do
                 x > 0 -> :positive
               end
             end
             """)
    end
  end

  describe "does not flag non-cond constructs" do
    test "if/else" do
      assert clean?("""
             def run(x) do
               if x > 0 do
                 :positive
               else
                 :non_positive
               end
             end
             """)
    end

    test "case with two clauses" do
      assert clean?("""
             def run(x) do
               case x > 0 do
                 true -> :positive
                 false -> :non_positive
               end
             end
             """)
    end

    test "plain function" do
      assert clean?("""
             defmodule M do
               def run(x), do: x * 2
             end
             """)
    end
  end

  describe "does not flag first clause being true" do
    test "true as first guard — unreachable second clause" do
      assert clean?("""
             def run(x) do
               cond do
                 true -> :always
                 x > 0 -> :never
               end
             end
             """)
    end
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoCondTwoClauses.fixable?() == true
    end
  end
end
