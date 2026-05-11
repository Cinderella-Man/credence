defmodule Credence.Pattern.NoCondTwoClausesFixTest do
  use ExUnit.Case

  defp fix(code) do
    result = Credence.Pattern.NoCondTwoClauses.fix(code, [])
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
        a =
          if x > 0 do
            :pos
          else
            :neg
          end

        b =
          if y > 0 do
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

  describe "does not modify cond with non-true second guard" do
    test "both guards are real conditions" do
      input = """
      def run(x) do
        cond do
          x > 0 -> :positive
          x <= 0 -> :non_positive
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
