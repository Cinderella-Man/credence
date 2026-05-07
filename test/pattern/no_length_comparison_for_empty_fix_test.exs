defmodule Credence.Pattern.NoLengthComparisonForEmptyFixTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoLengthComparisonForEmpty.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoLengthComparisonForEmpty.fix(code, [])
  end

  # ── exactly N ──────────────────────────────────────────────────

  describe "exactly N" do
    test "length(l) == 0 → l == []" do
      assert fix("length(l) == 0") == "l == []"
    end

    test "length(l) == 1 → match?([_], l)" do
      assert fix("length(l) == 1") == "match?([_], l)"
    end

    test "length(l) == 3 → match?([_, _, _], l)" do
      assert fix("length(l) == 3") == "match?([_, _, _], l)"
    end

    test "length(l) == 5 → match?([_, _, _, _, _], l)" do
      assert fix("length(l) == 5") == "match?([_, _, _, _, _], l)"
    end

    test "length(l) != 0 → l != []" do
      assert fix("length(l) != 0") == "l != []"
    end

    test "length(l) != 2 → !match?([_, _], l)" do
      assert fix("length(l) != 2") == "!match?([_, _], l)"
    end
  end

  # ── at least N ─────────────────────────────────────────────────

  describe "at least N" do
    test "length(l) > 0 → l != []" do
      assert fix("length(l) > 0") == "l != []"
    end

    test "length(l) >= 1 → l != []" do
      assert fix("length(l) >= 1") == "l != []"
    end

    test "length(l) >= 2 → match?([_, _ | _], l)" do
      assert fix("length(l) >= 2") == "match?([_, _ | _], l)"
    end

    test "length(l) > 2 → match?([_, _, _ | _], l)" do
      assert fix("length(l) > 2") == "match?([_, _, _ | _], l)"
    end

    test "length(l) >= 5 → match?([_, _, _, _, _ | _], l)" do
      assert fix("length(l) >= 5") == "match?([_, _, _, _, _ | _], l)"
    end
  end

  # ── fewer than N ───────────────────────────────────────────────

  describe "fewer than N" do
    test "length(l) < 1 → l == []" do
      assert fix("length(l) < 1") == "l == []"
    end

    test "length(l) <= 0 → l == []" do
      assert fix("length(l) <= 0") == "l == []"
    end

    test "length(l) < 2 → !match?([_, _ | _], l)" do
      assert fix("length(l) < 2") == "!match?([_, _ | _], l)"
    end

    test "length(l) <= 2 → !match?([_, _, _ | _], l)" do
      assert fix("length(l) <= 2") == "!match?([_, _, _ | _], l)"
    end

    test "length(l) < 5 → !match?([_, _, _, _, _ | _], l)" do
      assert fix("length(l) < 5") == "!match?([_, _, _, _, _ | _], l)"
    end
  end

  # ── reversed operands ──────────────────────────────────────────

  describe "reversed operands" do
    test "0 == length(l) → l == []" do
      assert fix("0 == length(l)") == "l == []"
    end

    test "2 <= length(l) → match?([_, _ | _], l)" do
      assert fix("2 <= length(l)") == "match?([_, _ | _], l)"
    end

    test "0 < length(l) → l != []" do
      assert fix("0 < length(l)") == "l != []"
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

      fixed = fix(code)
      assert fixed =~ "!match?([_, _ | _], nums)"
      refute fixed =~ "length(nums)"
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: length(list) >= 3
        def baz(y), do: y * 2
      end
      """

      fixed = fix(code)
      assert fixed =~ "def foo(x), do: x + 1"
      assert fixed =~ "match?([_, _, _ | _], list)"
      assert fixed =~ "def baz(y), do: y * 2"
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "returns source unchanged when nothing to fix" do
      code = "def run(list), do: list == []"
      assert fix(code) == code
    end

    test "does not touch length(l) > 5 (above max)" do
      code = "length(l) > 5"
      assert fix(code) == code
    end

    test "does not touch length(&1) > 1 (non-variable arg)" do
      code = "Enum.filter(groups, &(length(&1) > 1))"
      assert fix(code) == code
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

      assert check(fix(code)) == []
    end

    test "fixed code with non-variable args produces zero issues" do
      code = """
      defmodule Example do
        def run(groups) do
          Enum.filter(groups, &(length(&1) > 1))
        end
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(l), do: length(l) == 0
        def b(l), do: length(l) >= 2
        def c(l), do: length(l) < 5
      end
      """

      assert {:ok, _} = Code.string_to_quoted(fix(code))
    end
  end
end
