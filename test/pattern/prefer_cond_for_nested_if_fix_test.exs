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

    test "call, map and tuple bodies" do
      input = """
      if a == :ok do
        foo(a: 1, b: 2)
      else
        if b > 10 do
          %{a: 1, b: 2}
        else
          {:error, reason}
        end
      end
      """

      expected = """
      cond do
        a == :ok -> foo(a: 1, b: 2)
        b > 10 -> %{a: 1, b: 2}
        true -> {:error, reason}
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
  # SAFETY — must NOT modify (structural non-matches)
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

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify (outside the safe core)
  #
  # The fix reassembles each condition/body as a single `cond` clause line.
  # Conditions or bodies that contain a block form (if/case/cond/with/for/
  # fn/receive/try) or that render across multiple lines cannot be moved
  # this way without corrupting the result, so the rule leaves them alone.
  # ═══════════════════════════════════════════════════════════════════

  describe "flattens only the safe (innermost) level of deeper nestings" do
    test "three-level nesting flattens the inner two levels only" do
      input = """
      if a do
        1
      else
        if b do
          2
        else
          if c do
            3
          else
            4
          end
        end
      end
      """

      # The outer `if a` is left intact (its else body contains an `if`, so it
      # is outside the safe core). The inner `if b / if c` is a valid, simple
      # nesting and flattens. Only one (non-overlapping) patch is produced.
      expected = """
      if a do
        1
      else
        cond do
          b -> 2
          c -> 3
          true -> 4
        end
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), expected)
    end
  end

  describe "does not modify when a body is itself a block form" do
    test "an outer body contains a case expression" do
      input = """
      if x > 0 do
        case y do
          :a -> 1
          _ -> 2
        end
      else
        if x < 0 do
          "negative"
        else
          "zero"
        end
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), input)
    end

    test "an inner body is a multi-statement block" do
      input = """
      if x > 0 do
        "positive"
      else
        if x < 0 do
          a = 1
          a + 1
        else
          "zero"
        end
      end
      """

      confirm_fix(fix(PreferCondForNestedIf, input), input)
    end
  end
end
