defmodule Credence.Pattern.NoLengthComparisonForEmptyFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoLengthComparisonForEmpty
  alias Credence.RuleHelpers

  # ── exactly N ──────────────────────────────────────────────────

  describe "exactly N" do
    test "length(l) == 0 → l == []" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) == 0
             """) == """
             l == []
             """
    end

    test "length(l) == 1 → match?([_], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) == 1
             """) == """
             match?([_], l)
             """
    end

    test "length(l) == 3 → match?([_, _, _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) == 3
             """) == """
             match?([_, _, _], l)
             """
    end

    test "length(l) == 5 → match?([_, _, _, _, _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) == 5
             """) == """
             match?([_, _, _, _, _], l)
             """
    end

    test "length(l) != 0 → l != []" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) != 0
             """) == """
             l != []
             """
    end

    test "length(l) != 2 → !match?([_, _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) != 2
             """) == """
             !match?([_, _], l)
             """
    end
  end

  # ── at least N ─────────────────────────────────────────────────

  describe "at least N" do
    test "length(l) > 0 → l != []" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) > 0
             """) == """
             l != []
             """
    end

    test "length(l) >= 1 → l != []" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) >= 1
             """) == """
             l != []
             """
    end

    test "length(l) >= 2 → match?([_, _ | _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) >= 2
             """) == """
             match?([_, _ | _], l)
             """
    end

    test "length(l) > 2 → match?([_, _, _ | _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) > 2
             """) == """
             match?([_, _, _ | _], l)
             """
    end

    test "length(l) >= 5 → match?([_, _, _, _, _ | _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) >= 5
             """) == """
             match?([_, _, _, _, _ | _], l)
             """
    end
  end

  # ── fewer than N ───────────────────────────────────────────────

  describe "fewer than N" do
    test "length(l) < 1 → l == []" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) < 1
             """) == """
             l == []
             """
    end

    test "length(l) <= 0 → l == []" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) <= 0
             """) == """
             l == []
             """
    end

    test "length(l) < 2 → !match?([_, _ | _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) < 2
             """) == """
             !match?([_, _ | _], l)
             """
    end

    test "length(l) <= 2 → !match?([_, _, _ | _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) <= 2
             """) == """
             !match?([_, _, _ | _], l)
             """
    end

    test "length(l) < 5 → !match?([_, _, _, _, _ | _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             length(l) < 5
             """) == """
             !match?([_, _, _, _, _ | _], l)
             """
    end
  end

  # ── reversed operands ──────────────────────────────────────────

  describe "reversed operands" do
    test "0 == length(l) → l == []" do
      assert fix(NoLengthComparisonForEmpty, """
             0 == length(l)
             """) == """
             l == []
             """
    end

    test "2 <= length(l) → match?([_, _ | _], l)" do
      assert fix(NoLengthComparisonForEmpty, """
             2 <= length(l)
             """) == """
             match?([_, _ | _], l)
             """
    end

    test "0 < length(l) → l != []" do
      assert fix(NoLengthComparisonForEmpty, """
             0 < length(l)
             """) == """
             l != []
             """
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "fixes length check inside if" do
      code = """
      defmodule Example do
        def max_product(nums) do
          if length(nums) < 2 do
            raise ArgumentError, "need at least 2"
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def max_product(nums) do
          if !match?([_, _ | _], nums) do
            raise ArgumentError, "need at least 2"
          end
        end
      end
      """

      assert fix(NoLengthComparisonForEmpty, code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: length(list) >= 3
        def baz(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: match?([_, _, _ | _], list)
        def baz(y), do: y * 2
      end
      """

      assert fix(NoLengthComparisonForEmpty, code) == expected
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "returns source unchanged when nothing to fix" do
      code = """
      def run(list), do: list == []
      """

      assert fix(NoLengthComparisonForEmpty, code) == code
    end

    test "does not touch length(l) > 5 (above max)" do
      code = """
      length(l) > 5
      """

      assert fix(NoLengthComparisonForEmpty, code) == code
    end

    test "does not touch length(&1) > 1 (non-variable arg)" do
      code = """
      Enum.filter(groups, &(length(&1) > 1))
      """

      assert fix(NoLengthComparisonForEmpty, code) == code
    end

    test "does not touch qualified calls like String.length(s) >= 2" do
      code = """
      if String.length(query) >= 2, do: :ok
      """

      assert fix(NoLengthComparisonForEmpty, code) == code
    end
  end

  # ── round-trip ─────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(l), do: length(l) == 0
        def b(l), do: length(l) > 0
        def c(l), do: length(l) >= 3
        def d(l), do: length(l) < 2
        def e(l), do: 0 == length(l)
      end
      """

      assert check(NoLengthComparisonForEmpty, fix(NoLengthComparisonForEmpty, code)) == []
    end

    test "fixed code with non-variable args produces zero issues" do
      code = """
      defmodule Example do
        def run(groups) do
          Enum.filter(groups, &(length(&1) > 1))
        end
      end
      """

      assert check(NoLengthComparisonForEmpty, fix(NoLengthComparisonForEmpty, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(l), do: length(l) == 0
        def b(l), do: length(l) >= 2
        def c(l), do: length(l) < 5
      end
      """

      assert valid_syntax?(fix(NoLengthComparisonForEmpty, code))
    end
  end

  describe "guard-context safety (issue: match? is not guard-safe)" do
    test "does not rewrite length comparison inside a function-head guard" do
      code = """
      defmodule Test do
        def from_state(state) when is_list(state) and length(state) == 4, do: state
      end
      """

      output = fix(NoLengthComparisonForEmpty, code)

      assert output == code
      assert valid_syntax?(output)
      # And the fixed output must still compile (the actual symptom).
      assert RuleHelpers.compiles?(output)
    end

    test "does not rewrite length comparison inside a case-clause guard" do
      code = """
      case x do
        l when length(l) >= 3 -> :big
        _ -> :other
      end
      """

      assert fix(NoLengthComparisonForEmpty, code) == code
    end

    test "still rewrites length comparison in the body even when a guard exists" do
      code = """
      defmodule Test do
        def f(state) when is_list(state) do
          length(state) == 0
        end
      end
      """

      # Guard untouched, body rewritten to `state == []`.
      expected = """
      defmodule Test do
        def f(state) when is_list(state) do
          state == []
        end
      end
      """

      assert fix(NoLengthComparisonForEmpty, code) == expected
    end
  end
end
