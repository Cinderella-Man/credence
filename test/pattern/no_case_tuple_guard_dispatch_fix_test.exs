defmodule Credence.Pattern.NoCaseTupleGuardDispatchFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCaseTupleGuardDispatch

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(NoCaseTupleGuardDispatch, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC FIXES — case → cond
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites case on tuple to cond" do
    test "two-tuple with two guards and wildcard catch-all" do
      input = """
      def run(e1, e2) do
        case {e1, e2} do
          {e1, e2} when e1 < e2 -> :left
          {e1, e2} when e1 > e2 -> :right
          _ -> :equal
        end
      end
      """

      expected = """
      def run(e1, e2) do
        cond do
          e1 < e2 -> :left
          e1 > e2 -> :right
          true -> :equal
        end
      end
      """

      assert fix(input) == expected
    end

    test "two-tuple with two guards and explicit catch-all" do
      input = """
      def run(e1, e2) do
        case {e1, e2} do
          {e1, e2} when e1 < e2 -> :left
          {e1, e2} when e1 > e2 -> :right
          {e1, e2} -> :equal
        end
      end
      """

      expected = """
      def run(e1, e2) do
        cond do
          e1 < e2 -> :left
          e1 > e2 -> :right
          true -> :equal
        end
      end
      """

      assert fix(input) == expected
    end

    test "multi-line bodies" do
      input = """
      def run(e1, e2) do
        case {e1, e2} do
          {e1, e2} when e1 < e2 ->
            x = e1 + e2
            process(x)
          _ ->
            :equal
        end
      end
      """

      expected = """
      def run(e1, e2) do
        cond do
          e1 < e2 ->
            x = e1 + e2
            process(x)

          true ->
            :equal
        end
      end
      """

      assert fix(input) == expected
    end

    test "three-tuple with guards" do
      input = """
      def run(a, b, c) do
        case {a, b, c} do
          {a, b, c} when a < b and b < c -> :ascending
          {a, b, c} when a > b and b > c -> :descending
          {a, b, c} -> :other
        end
      end
      """

      expected = """
      def run(a, b, c) do
        cond do
          a < b and b < c -> :ascending
          a > b and b > c -> :descending
          true -> :other
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify case with structural patterns" do
    test "atom patterns" do
      input = """
      def run(x) do
        case x do
          :ok -> :success
          :error -> :failure
        end
      end
      """

      assert fix(input) == input
    end

    test "tuple destructure patterns" do
      input = """
      def run(x) do
        case x do
          {:ok, val} -> val
          {:error, _} -> :default
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify case without guards" do
    test "structural dispatch only" do
      input = """
      def run(x) do
        case x do
          {0, y} -> y
          {x, 0} -> x
          _ -> x + y
        end
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify case on non-tuple" do
    test "case on variable" do
      input = """
      def run(x) do
        case x do
          y when y > 0 -> :positive
          _ -> :non_positive
        end
      end
      """

      assert fix(input) == input
    end
  end
end
