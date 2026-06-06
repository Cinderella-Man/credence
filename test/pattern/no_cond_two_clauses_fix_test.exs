defmodule Credence.Pattern.NoCondTwoClausesFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCondTwoClauses

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(NoCondTwoClauses, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC FIXES — cond → if/else
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites two-clause cond to if/else" do
    test "basic case" do
      input = """
      def run(x) do
        cond do
          x > 0 -> :positive
          true -> :non_positive
        end
      end
      """

      expected = """
      def run(x) do
        if x > 0 do
          :positive
        else
          :non_positive
        end
      end
      """

      assert fix(input) == expected
    end

    test "multi-line second body — idx=50 pattern" do
      input = """
      def run(low, high, target) do
        cond do
          low > high ->
            false
          true ->
            mid = div(low + high, 2)
            search(mid, target)
        end
      end
      """

      expected = """
      def run(low, high, target) do
        if low > high do
          false
        else
          mid = div(low + high, 2)
          search(mid, target)
        end
      end
      """

      assert fix(input) == expected
    end

    test "multi-line first body" do
      input = """
      def run(list) do
        cond do
          Enum.empty?(list) ->
            log(:empty)
            :default
          true ->
            hd(list)
        end
      end
      """

      expected = """
      def run(list) do
        if Enum.empty?(list) do
          log(:empty)
          :default
        else
          hd(list)
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "rewrites complementary guard cond to if/else" do
    test "complementary guards — <= and >" do
      input = """
      def run(x, target) do
        cond do
          x <= target -> :left
          x > target -> :right
        end
      end
      """

      expected = """
      def run(x, target) do
        if x <= target do
          :left
        else
          :right
        end
      end
      """

      assert fix(input) == expected
    end

    test "complementary guards — < and >=" do
      input = """
      def run(x, y) do
        cond do
          x < y -> :less
          x >= y -> :not_less
        end
      end
      """

      expected = """
      def run(x, y) do
        if x < y do
          :less
        else
          :not_less
        end
      end
      """

      assert fix(input) == expected
    end

    test "complementary guards — == and !=" do
      input = """
      def run(x, y) do
        cond do
          x == y -> :equal
          x != y -> :not_equal
        end
      end
      """

      expected = """
      def run(x, y) do
        if x == y do
          :equal
        else
          :not_equal
        end
      end
      """

      assert fix(input) == expected
    end

    test "complementary guards — binary search pattern" do
      input = """
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
      """

      expected = """
      def search(tuple, target, low, high) do
        mid = div(low + high, 2)
        mid_char = elem(tuple, mid)

        if mid_char <= target do
          search(tuple, target, mid + 1, high)
        else
          if mid == 0 or elem(tuple, mid - 1) <= target do
            mid
          else
            search(tuple, target, low, mid - 1)
          end
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # COMPLEX CONDITIONS — preserved as-is
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves complex conditions" do
    test "and condition" do
      input = """
      def run(x, y) do
        cond do
          x > 0 and y > 0 -> :both_positive
          true -> :not_both
        end
      end
      """

      expected = """
      def run(x, y) do
        if x > 0 and y > 0 do
          :both_positive
        else
          :not_both
        end
      end
      """

      assert fix(input) == expected
    end

    test "function call condition" do
      input = """
      def run(list) do
        cond do
          Enum.empty?(list) -> :empty
          true -> hd(list)
        end
      end
      """

      expected = """
      def run(list) do
        if Enum.empty?(list) do
          :empty
        else
          hd(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "negated condition" do
      input = """
      def run(x) do
        cond do
          not is_nil(x) -> x
          true -> :default
        end
      end
      """

      expected = """
      def run(x) do
        if not is_nil(x) do
          x
        else
          :default
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CONTEXT — modules, surrounding code
  # ═══════════════════════════════════════════════════════════════════

  describe "works in different contexts" do
    test "inside a module" do
      input = """
      defmodule Search do
        def binary_search(low, high) do
          cond do
            low > high -> false
            true -> :continue
          end
        end
      end
      """

      expected = """
      defmodule Search do
        def binary_search(low, high) do
          if low > high do
            false
          else
            :continue
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves surrounding code" do
      input = """
      def run(x) do
        setup()
        cond do
          x > 0 -> :positive
          true -> :non_positive
        end
      end
      """

      expected = """
      def run(x) do
        setup()
        if x > 0 do
          :positive
        else
          :non_positive
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes multiple occurrences" do
    test "two conds in same function" do
      input = """
      def run(x, y) do
        a = cond do
          x > 0 -> :pos
          true -> :neg
        end
        b = cond do
          y > 0 -> :pos
          true -> :neg
        end
        {a, b}
      end
      """

      expected = """
      def run(x, y) do
        a = if x > 0 do
          :pos
        else
          :neg
        end
        b = if y > 0 do
          :pos
        else
          :neg
        end
        {a, b}
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify cond with 3+ clauses" do
    test "three clauses" do
      input = """
      def run(x) do
        cond do
          x > 0 -> :positive
          x == 0 -> :zero
          true -> :negative
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify cond with non-true non-complementary second guard" do
    test "non-complementary guards" do
      input = """
      def run(x) do
        cond do
          x > 100 -> :high
          x > 0 -> :low_positive
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify complementary guards with non-simple operands" do
    # Re-evaluating a side-effecting operand in the second guard makes the
    # rewrite unsafe, so call/expression operands are left untouched.
    test "function-call operand" do
      input = """
      def run(target) do
        cond do
          next_id() <= target -> :left
          next_id() > target -> :right
        end
      end
      """

      assert fix(input) == input
    end

    test "arithmetic-expression operand" do
      input = """
      def run(x, y) do
        cond do
          x + 1 <= y -> :left
          x + 1 > y -> :right
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify cond with 1 clause" do
    test "single clause" do
      input = """
      def run(x) do
        cond do
          x > 0 -> :positive
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify non-cond code" do
    test "if/else is unchanged" do
      input = """
      def run(x) do
        if x > 0 do
          :positive
        else
          :non_positive
        end
      end
      """

      assert fix(input) == input
    end

    test "plain function" do
      input = """
      defmodule M do
        def run(x), do: x * 2
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify first clause being true" do
    test "true as first guard" do
      input = """
      def run(x) do
        cond do
          true -> :always
          x > 0 -> :never
        end
      end
      """

      assert fix(input) == input
    end
  end
end
