defmodule Credence.Pattern.NoCondTwoClausesCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCondTwoClauses

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags cond with exactly 2 clauses where second is true" do
    test "basic case" do
      assert flagged?(NoCondTwoClauses, """
             def run(x) do
               cond do
                 x > 0 -> :positive
                 true -> :non_positive
               end
             end
             """)
    end

    test "complex first guard" do
      assert flagged?(NoCondTwoClauses, """
             def run(x, y) do
               cond do
                 x > 0 and y > 0 -> :both_positive
                 true -> :not_both
               end
             end
             """)
    end

    test "function call as first guard" do
      assert flagged?(NoCondTwoClauses, """
             def run(list) do
               cond do
                 Enum.empty?(list) -> :empty
                 true -> hd(list)
               end
             end
             """)
    end

    test "multi-line bodies" do
      assert flagged?(NoCondTwoClauses, """
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
      assert flagged?(NoCondTwoClauses, """
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
      assert flagged?(NoCondTwoClauses, """
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

      assert length(check(NoCondTwoClauses, code)) == 2
    end

    test "inside other constructs" do
      assert flagged?(NoCondTwoClauses, """
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

  describe "flags cond with exactly 2 clauses where second is the complement" do
    test "complementary guards — <= and >" do
      assert flagged?(NoCondTwoClauses, """
             def run(x, target) do
               cond do
                 x <= target -> :left
                 x > target -> :right
               end
             end
             """)
    end

    test "complementary guards — < and >=" do
      assert flagged?(NoCondTwoClauses, """
             def run(x, y) do
               cond do
                 x < y -> :less
                 x >= y -> :not_less
               end
             end
             """)
    end

    test "complementary guards — == and !=" do
      assert flagged?(NoCondTwoClauses, """
             def run(x, y) do
               cond do
                 x == y -> :equal
                 x != y -> :not_equal
               end
             end
             """)
    end

    test "complementary guards — reversed order (first is >, second is <=)" do
      assert flagged?(NoCondTwoClauses, """
             def run(x, target) do
               cond do
                 x > target -> :right
                 x <= target -> :left
               end
             end
             """)
    end

    test "complementary guards in binary search pattern — idx=61326" do
      assert flagged?(NoCondTwoClauses, """
             def search(tuple, target, low, high) do
               mid = div(low + high, 2)
               mid_char = elem(tuple, mid)
               cond do
                 mid_char <= target ->
                   search(tuple, target, mid + 1, high)
                 mid_char > target ->
                   if mid == 0 or elem(tuple, mid - 1) <= target do
                     mid
                   else
                     search(tuple, target, low, mid - 1)
                   end
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
      assert clean?(NoCondTwoClauses, """
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
      assert clean?(NoCondTwoClauses, """
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
    test "non-complementary guards" do
      assert clean?(NoCondTwoClauses, """
             def run(x) do
               cond do
                 x > 100 -> :high
                 x > 0 -> :low_positive
               end
             end
             """)
    end

    test "second guard is a function call" do
      assert clean?(NoCondTwoClauses, """
             def run(x) do
               cond do
                 x > 0 -> :positive
                 is_nil(x) -> :nil_value
               end
             end
             """)
    end
  end

  describe "does not flag complementary guards with non-simple operands" do
    # A `cond`'s second guard is re-evaluated when the first is false, so the
    # rewrite is only safe when operands carry no side effects. Function-call
    # operands could observe different state on the re-run, so they are not
    # flagged even though the operators are complementary.
    test "left operand is a function call" do
      assert clean?(NoCondTwoClauses, """
             def run(target) do
               cond do
                 next_id() <= target -> :left
                 next_id() > target -> :right
               end
             end
             """)
    end

    test "right operand is a function call" do
      assert clean?(NoCondTwoClauses, """
             def run(x) do
               cond do
                 x == fetch() -> :equal
                 x != fetch() -> :not_equal
               end
             end
             """)
    end

    test "operand is an arithmetic expression" do
      assert clean?(NoCondTwoClauses, """
             def run(x, y) do
               cond do
                 x + 1 <= y -> :left
                 x + 1 > y -> :right
               end
             end
             """)
    end
  end

  describe "does not flag cond with 1 clause" do
    test "single clause" do
      assert clean?(NoCondTwoClauses, """
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
      assert clean?(NoCondTwoClauses, """
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
      assert clean?(NoCondTwoClauses, """
             def run(x) do
               case x > 0 do
                 true -> :positive
                 false -> :non_positive
               end
             end
             """)
    end

    test "plain function" do
      assert clean?(NoCondTwoClauses, """
             defmodule M do
               def run(x), do: x * 2
             end
             """)
    end
  end

  describe "does not flag first clause being true" do
    test "true as first guard — unreachable second clause" do
      assert clean?(NoCondTwoClauses, """
             def run(x) do
               cond do
                 true -> :always
                 x > 0 -> :never
               end
             end
             """)
    end
  end
end
