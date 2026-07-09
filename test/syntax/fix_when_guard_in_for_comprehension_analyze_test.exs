defmodule Credence.Syntax.FixWhenGuardInForComprehensionAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixWhenGuardInForComprehension

  defp analyze(code), do: FixWhenGuardInForComprehension.analyze(code)

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — single-line for comprehension with `when` filter
  # ═══════════════════════════════════════════════════════════════════

  describe "flags single-line for comprehension with when filter" do
    test "tuple pattern with when filter" do
      code = """
      for {name, price, _qty} <- items, when price > 100 do
        name
      end
      """

      assert [%Issue{rule: :fix_when_guard_in_for_comprehension}] = analyze(code)
    end

    test "simple variable pattern with when filter" do
      code = """
      for x <- list, when x > 5 do
        x
      end
      """

      assert [%Issue{rule: :fix_when_guard_in_for_comprehension}] = analyze(code)
    end

    test "two-element tuple with when filter" do
      code = """
      for {k, v} <- map, when v != nil do
        k
      end
      """

      assert [%Issue{rule: :fix_when_guard_in_for_comprehension}] = analyze(code)
    end

    test "range generator with when filter" do
      code = """
      for n <- 1..10, when rem(n, 2) == 0 do
        n
      end
      """

      assert [%Issue{rule: :fix_when_guard_in_for_comprehension}] = analyze(code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — multi-line for comprehension with `when` on next line
  # ═══════════════════════════════════════════════════════════════════

  describe "flags multi-line for comprehension with when on next line" do
    test "when on continuation line" do
      code = """
      for {name, price, _qty} <- items,
          when price > 100 do
        name
      end
      """

      assert [%Issue{rule: :fix_when_guard_in_for_comprehension, meta: %{line: 2}}] = analyze(code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — in module context
  # ═══════════════════════════════════════════════════════════════════

  describe "flags in module context" do
    test "inside defmodule and def" do
      code = """
      defmodule M do
        def filter_expensive(items) do
          for {name, price, _qty} <- items, when price > 100 do
            name
          end
        end
      end
      """

      assert [%Issue{rule: :fix_when_guard_in_for_comprehension, meta: %{line: 3}}] = analyze(code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — already correct for comprehension
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag already correct code" do
    test "for comprehension with bare filter (no when)" do
      code = """
      for {name, price, _qty} <- items, price > 100 do
        name
      end
      """

      assert analyze(code) == []
    end

    test "for comprehension with rem filter" do
      code = """
      for n <- 1..10, rem(n, 2) == 0 do
        n
      end
      """

      assert analyze(code) == []
    end

    test "for comprehension without any filter" do
      code = "for x <- list, do: x"

      assert analyze(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — `when` in other valid contexts
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when in other contexts" do
    test "function guard" do
      code = "def foo(x) when x > 0, do: x"

      assert analyze(code) == []
    end

    test "case clause guard" do
      code = """
      case x do
        n when n > 0 -> :positive
        _ -> :zero
      end
      """

      assert analyze(code) == []
    end

    test "when as keyword key" do
      code = "%{when: true}"

      assert analyze(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — comments
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag comments" do
    test "comment mentioning when filter" do
      code = "# for x <- list, when x > 0 do"

      assert analyze(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # METADATA
  # ═══════════════════════════════════════════════════════════════════

  describe "metadata" do
    test "reports correct line number" do
      code = """
      x = 1
      for {name, price, _qty} <- items, when price > 100 do
        name
      end
      """

      [issue] = analyze(code)
      assert issue.meta.line == 2
    end
  end
end
