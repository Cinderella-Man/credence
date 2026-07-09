defmodule Credence.Syntax.FixWhenGuardInForComprehensionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixWhenGuardInForComprehension

  defp analyze(code), do: FixWhenGuardInForComprehension.analyze(code)
  defp fix(code), do: FixWhenGuardInForComprehension.fix(code)

  # ═══════════════════════════════════════════════════════════════════
  # FIXES — single-line for comprehension with `when` filter
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes single-line for comprehension" do
    test "tuple pattern with when filter" do
      input = """
      for {name, price, _qty} <- items, when price > 100 do
        name
      end
      """

      expected = """
      for {name, price, _qty} <- items, price > 100 do
        name
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "simple variable pattern with when filter" do
      input = """
      for x <- list, when x > 5 do
        x
      end
      """

      expected = """
      for x <- list, x > 5 do
        x
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "two-element tuple with when filter" do
      input = """
      for {k, v} <- map, when v != nil do
        k
      end
      """

      expected = """
      for {k, v} <- map, v != nil do
        k
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "range generator with when filter" do
      input = """
      for n <- 1..10, when rem(n, 2) == 0 do
        n
      end
      """

      expected = """
      for n <- 1..10, rem(n, 2) == 0 do
        n
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXES — multi-line for comprehension
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes multi-line for comprehension" do
    test "when on continuation line" do
      input = """
      for {name, price, _qty} <- items,
          when price > 100 do
        name
      end
      """

      expected = """
      for {name, price, _qty} <- items,
          price > 100 do
        name
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXES — in module context
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes in module context" do
    test "inside defmodule and def" do
      input = """
      defmodule M do
        def filter_expensive(items) do
          for {name, price, _qty} <- items, when price > 100 do
            name
          end
        end
      end
      """

      expected = """
      defmodule M do
        def filter_expensive(items) do
          for {name, price, _qty} <- items, price > 100 do
            name
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ROUND-TRIP — fixed output no longer flags
  # ═══════════════════════════════════════════════════════════════════

  describe "round-trip" do
    test "fixed output no longer flags" do
      input = """
      for {name, price, _qty} <- items, when price > 100 do
        name
      end
      """

      assert analyze(fix(input)) == []
    end

    test "fixed multi-line output no longer flags" do
      input = """
      for {name, price, _qty} <- items,
          when price > 100 do
        name
      end
      """

      assert analyze(fix(input)) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # VALID SYNTAX — fixed output parses
  # ═══════════════════════════════════════════════════════════════════

  describe "fix output is well-formed" do
    test "single-line fix parses" do
      input = """
      for {name, price, _qty} <- items, when price > 100 do
        name
      end
      """

      assert valid_syntax?(fix(input))
    end

    test "multi-line fix parses" do
      input = """
      for {name, price, _qty} <- items,
          when price > 100 do
        name
      end
      """

      assert valid_syntax?(fix(input))
    end

    test "module-level fix parses" do
      input = """
      defmodule M do
        def filter_expensive(items) do
          for {name, price, _qty} <- items, when price > 100 do
            name
          end
        end
      end
      """

      assert valid_syntax?(fix(input))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — already correct code
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch already correct code" do
    test "for comprehension with bare filter" do
      code = """
      for {name, price, _qty} <- items, price > 100 do
        name
      end
      """

      confirm_fix(fix(code), code)
    end

    test "for comprehension without filter" do
      code = "for x <- list, do: x"

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — `when` in other valid contexts
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch when in other contexts" do
    test "function guard unchanged" do
      code = "def foo(x) when x > 0, do: x"

      confirm_fix(fix(code), code)
    end

    test "case clause guard unchanged" do
      code = """
      case x do
        n when n > 0 -> :positive
        _ -> :zero
      end
      """

      confirm_fix(fix(code), code)
    end
  end
end
