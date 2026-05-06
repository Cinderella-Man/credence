defmodule Credence.Pattern.NoLengthComparisonForEmptyTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoLengthComparisonForEmpty.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoLengthComparisonForEmpty.fix(code, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoLengthComparisonForEmpty.fixable?() == true
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — equality
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — equality" do
    test "flags length(list) == 0" do
      code = "defmodule E do\n  def r(l), do: length(l) == 0\nend"
      [issue] = check(code)
      assert issue.rule == :no_length_comparison_for_empty
    end

    test "flags length(list) == 3" do
      code = "defmodule E do\n  def r(l), do: length(l) == 3\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) == 5" do
      code = "defmodule E do\n  def r(l), do: length(l) == 5\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) != 0" do
      code = "defmodule E do\n  def r(l), do: length(l) != 0\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) != 2" do
      code = "defmodule E do\n  def r(l), do: length(l) != 2\nend"
      assert length(check(code)) == 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — at least N
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — at least N" do
    test "flags length(list) > 0" do
      code = "defmodule E do\n  def r(l), do: length(l) > 0\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) >= 2" do
      code = "defmodule E do\n  def r(l), do: length(l) >= 2\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) > 3" do
      code = "defmodule E do\n  def r(l), do: length(l) > 3\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) >= 5" do
      code = "defmodule E do\n  def r(l), do: length(l) >= 5\nend"
      assert length(check(code)) == 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — fewer than N
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — fewer than N" do
    test "flags length(list) < 1" do
      code = "defmodule E do\n  def r(l), do: length(l) < 1\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) < 2" do
      code = "defmodule E do\n  def r(l), do: length(l) < 2\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) <= 3" do
      code = "defmodule E do\n  def r(l), do: length(l) <= 3\nend"
      assert length(check(code)) == 1
    end

    test "flags length(list) < 5" do
      code = "defmodule E do\n  def r(l), do: length(l) < 5\nend"
      assert length(check(code)) == 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — reversed operands
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — reversed operands" do
    test "flags 0 == length(list)" do
      code = "defmodule E do\n  def r(l), do: 0 == length(l)\nend"
      assert length(check(code)) == 1
    end

    test "flags 2 <= length(list) (means >= 2)" do
      code = "defmodule E do\n  def r(l), do: 2 <= length(l)\nend"
      assert length(check(code)) == 1
    end

    test "flags 0 < length(list) (means > 0)" do
      code = "defmodule E do\n  def r(l), do: 0 < length(l)\nend"
      assert length(check(code)) == 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — negative cases
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — negative cases" do
    test "does not flag length(list) == 6 (above max)" do
      code = "defmodule E do\n  def r(l), do: length(l) == 6\nend"
      assert check(code) == []
    end

    test "does not flag length(list) > 5 (would need 6 underscores)" do
      code = "defmodule E do\n  def r(l), do: length(l) > 5\nend"
      assert check(code) == []
    end

    test "does not flag length(list) >= 6" do
      code = "defmodule E do\n  def r(l), do: length(l) >= 6\nend"
      assert check(code) == []
    end

    test "does not flag list == []" do
      code = "defmodule E do\n  def r(l), do: l == []\nend"
      assert check(code) == []
    end

    test "does not flag match? patterns" do
      code = "defmodule E do\n  def r(l), do: match?([_, _ | _], l)\nend"
      assert check(code) == []
    end

    test "does not flag length in arithmetic" do
      code = "defmodule E do\n  def r(l), do: length(l) + 1\nend"
      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — exactly N
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — exactly N" do
    test "length(l) == 0 → l == []" do
      code = "defmodule E do\n  def r(l), do: length(l) == 0\nend"
      assert fix(code) =~ "l == []"
    end

    test "length(l) == 1 → match?([_], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) == 1\nend"
      assert fix(code) =~ "match?([_], l)"
    end

    test "length(l) == 3 → match?([_, _, _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) == 3\nend"
      assert fix(code) =~ "match?([_, _, _], l)"
    end

    test "length(l) == 5 → match?([_, _, _, _, _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) == 5\nend"
      assert fix(code) =~ "match?([_, _, _, _, _], l)"
    end

    test "length(l) != 0 → l != []" do
      code = "defmodule E do\n  def r(l), do: length(l) != 0\nend"
      assert fix(code) =~ "l != []"
    end

    test "length(l) != 2 → !match?([_, _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) != 2\nend"
      assert fix(code) =~ "!match?([_, _], l)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — at least N
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — at least N" do
    test "length(l) > 0 → l != []" do
      code = "defmodule E do\n  def r(l), do: length(l) > 0\nend"
      assert fix(code) =~ "l != []"
    end

    test "length(l) >= 1 → l != []" do
      code = "defmodule E do\n  def r(l), do: length(l) >= 1\nend"
      assert fix(code) =~ "l != []"
    end

    test "length(l) >= 2 → match?([_, _ | _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) >= 2\nend"
      assert fix(code) =~ "match?([_, _ | _], l)"
    end

    test "length(l) > 2 → match?([_, _, _ | _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) > 2\nend"
      assert fix(code) =~ "match?([_, _, _ | _], l)"
    end

    test "length(l) >= 5 → match?([_, _, _, _, _ | _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) >= 5\nend"
      assert fix(code) =~ "match?([_, _, _, _, _ | _], l)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — fewer than N
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — fewer than N" do
    test "length(l) < 1 → l == []" do
      code = "defmodule E do\n  def r(l), do: length(l) < 1\nend"
      assert fix(code) =~ "l == []"
    end

    test "length(l) <= 0 → l == []" do
      code = "defmodule E do\n  def r(l), do: length(l) <= 0\nend"
      assert fix(code) =~ "l == []"
    end

    test "length(l) < 2 → !match?([_, _ | _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) < 2\nend"
      assert fix(code) =~ "!match?([_, _ | _], l)"
    end

    test "length(l) <= 2 → !match?([_, _, _ | _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) <= 2\nend"
      assert fix(code) =~ "!match?([_, _, _ | _], l)"
    end

    test "length(l) < 5 → !match?([_, _, _, _, _ | _], l)" do
      code = "defmodule E do\n  def r(l), do: length(l) < 5\nend"
      assert fix(code) =~ "!match?([_, _, _, _, _ | _], l)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — reversed operands
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — reversed operands" do
    test "0 == length(l) → l == []" do
      code = "defmodule E do\n  def r(l), do: 0 == length(l)\nend"
      assert fix(code) =~ "l == []"
    end

    test "2 <= length(l) → match?([_, _ | _], l)" do
      code = "defmodule E do\n  def r(l), do: 2 <= length(l)\nend"
      assert fix(code) =~ "match?([_, _ | _], l)"
    end

    test "0 < length(l) → l != []" do
      code = "defmodule E do\n  def r(l), do: 0 < length(l)\nend"
      assert fix(code) =~ "l != []"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — realistic context
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — realistic context" do
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

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def run(list), do: list == []
      end
      """

      assert fix(code) == code
    end

    test "does not touch length(list) > 5" do
      code = """
      defmodule Example do
        def run(list), do: length(list) > 5
      end
      """

      assert fix(code) == code
    end
  end
end
