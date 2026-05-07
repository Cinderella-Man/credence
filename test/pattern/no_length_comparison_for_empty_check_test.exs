defmodule Credence.Pattern.NoLengthComparisonForEmptyCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoLengthComparisonForEmpty.check(ast, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoLengthComparisonForEmpty.fixable?() == true
    end
  end

  # ── flags equality ─────────────────────────────────────────────

  describe "flags equality" do
    test "length(l) == 0" do
      assert [%Issue{rule: :no_length_comparison_for_empty}] = check("length(l) == 0")
    end

    test "length(l) == 3" do
      assert [%Issue{}] = check("length(l) == 3")
    end

    test "length(l) == 5" do
      assert [%Issue{}] = check("length(l) == 5")
    end

    test "length(l) != 0" do
      assert [%Issue{}] = check("length(l) != 0")
    end

    test "length(l) != 2" do
      assert [%Issue{}] = check("length(l) != 2")
    end
  end

  # ── flags at-least-N ───────────────────────────────────────────

  describe "flags at-least-N" do
    test "length(l) > 0" do
      assert [%Issue{}] = check("length(l) > 0")
    end

    test "length(l) >= 2" do
      assert [%Issue{}] = check("length(l) >= 2")
    end

    test "length(l) > 3" do
      assert [%Issue{}] = check("length(l) > 3")
    end

    test "length(l) >= 5" do
      assert [%Issue{}] = check("length(l) >= 5")
    end
  end

  # ── flags fewer-than-N ─────────────────────────────────────────

  describe "flags fewer-than-N" do
    test "length(l) < 1" do
      assert [%Issue{}] = check("length(l) < 1")
    end

    test "length(l) < 2" do
      assert [%Issue{}] = check("length(l) < 2")
    end

    test "length(l) <= 3" do
      assert [%Issue{}] = check("length(l) <= 3")
    end

    test "length(l) < 5" do
      assert [%Issue{}] = check("length(l) < 5")
    end
  end

  # ── flags reversed operands ────────────────────────────────────

  describe "flags reversed operands" do
    test "0 == length(l)" do
      assert [%Issue{}] = check("0 == length(l)")
    end

    test "2 <= length(l)" do
      assert [%Issue{}] = check("2 <= length(l)")
    end

    test "0 < length(l)" do
      assert [%Issue{}] = check("0 < length(l)")
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "length(l) == 6 (above max)" do
      assert check("length(l) == 6") == []
    end

    test "length(l) > 5 (would need 6 underscores)" do
      assert check("length(l) > 5") == []
    end

    test "length(l) >= 6" do
      assert check("length(l) >= 6") == []
    end

    test "list == [] (already fixed form)" do
      assert check("l == []") == []
    end

    test "match? pattern (already fixed form)" do
      assert check("match?([_, _ | _], l)") == []
    end

    test "length in arithmetic (not a comparison)" do
      assert check("length(l) + 1") == []
    end

    test "multiple violations in one module" do
      code = """
      defmodule E do
        def f(l), do: length(l) == 0
        def g(l), do: length(l) > 3
      end
      """

      assert length(check(code)) == 2
    end
  end

  # ── does NOT flag non-variable args (regression) ───────────────

  describe "does NOT flag non-variable arguments (regression)" do
    test "length(&1) > 1 (capture arg)" do
      assert check("Enum.filter(groups, &(length(&1) > 1))") == []
    end

    test "length(hd(x)) == 0 (call arg)" do
      assert check("length(hd(x)) == 0") == []
    end

    test "length(Map.get(m, k)) > 0 (dot-call arg)" do
      assert check("length(Map.get(m, k)) > 0") == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "meta.line is set" do
      [issue] = check("length(l) == 0")
      assert issue.meta.line != nil
    end
  end
end
