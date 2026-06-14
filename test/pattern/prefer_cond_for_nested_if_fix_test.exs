defmodule Credence.Pattern.PreferCondForNestedIfFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferCondForNestedIf

  # ═══════════════════════════════════════════════════════════════════
  # BASIC FIXES — nested if/else → cond
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites nested if/else to cond" do
    test "basic nested if/else" do
      input = """
      if x > 0 do
        "positive"
      else
        if x < 0 do
          "negative"
        else
          "zero"
        end
      end
      """

      expected = """
      cond do
        x > 0 -> "positive"
        x < 0 -> "negative"
        true -> "zero"
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), expected)
    end

    test "inside a function" do
      input = """
      def test(x) do
        if x > 0 do
          "positive"
        else
          if x < 0 do
            "negative"
          else
            "zero"
          end
        end
      end
      """

      expected = """
      def test(x) do
        cond do
          x > 0 -> "positive"
          x < 0 -> "negative"
          true -> "zero"
        end
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), expected)
    end

    test "inside a module" do
      input = """
      defmodule Example do
        def test(x) do
          if x > 0 do
            "positive"
          else
            if x < 0 do
              "negative"
            else
              "zero"
            end
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def test(x) do
          cond do
            x > 0 -> "positive"
            x < 0 -> "negative"
            true -> "zero"
          end
        end
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), expected)
    end

    test "different conditions and atom bodies" do
      input = """
      if a == :ok do
        :first
      else
        if b > 10 do
          :second
        else
          :third
        end
      end
      """

      expected = """
      cond do
        a == :ok -> :first
        b > 10 -> :second
        true -> :third
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CONTEXT — inside modules, with surrounding code
  # ═══════════════════════════════════════════════════════════════════

  describe "works in different contexts" do
    test "preserves surrounding code" do
      input = """
      def run(x) do
        setup()
        if x > 0 do
          "positive"
        else
          if x < 0 do
            "negative"
          else
            "zero"
          end
        end
      end
      """

      expected = """
      def run(x) do
        setup()
        cond do
          x > 0 -> "positive"
          x < 0 -> "negative"
          true -> "zero"
        end
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), expected)
    end

    test "used as expression assignment" do
      input = """
      def run(x) do
        result = if x > 0 do
          "positive"
        else
          if x < 0 do
            "negative"
          else
            "zero"
          end
        end
        result
      end
      """

      expected = """
      def run(x) do
        result = cond do
          x > 0 -> "positive"
          x < 0 -> "negative"
          true -> "zero"
        end
        result
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify if without else" do
    test "simple if" do
      input = """
      if x > 0 do
        "positive"
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), input)
    end
  end

  describe "does not modify if/else without nested if" do
    test "simple if/else" do
      input = """
      if x > 0 do
        "positive"
      else
        "non-positive"
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), input)
    end
  end

  describe "does not modify inner if without else" do
    test "inner if has no else" do
      input = """
      if x > 0 do
        "positive"
      else
        if x < 0 do
          "negative"
        end
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), input)
    end
  end

  describe "does not modify non-if code" do
    test "cond expression" do
      input = """
      cond do
        x > 0 -> "positive"
        x < 0 -> "negative"
        true -> "zero"
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), input)
    end

    test "plain function" do
      input = "def run(x), do: x * 2"

      confirm_fix(fix(PreferCondForNestedIf, input), input)
    end
  end
end
