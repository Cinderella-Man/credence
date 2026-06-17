defmodule Credence.Pattern.NoLengthComparisonForEmptyCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoLengthComparisonForEmpty

  # ── flags equality ─────────────────────────────────────────────

  describe "flags equality" do
    test "length(l) == 0" do
      assert [%Issue{rule: :no_length_comparison_for_empty}] =
               check(NoLengthComparisonForEmpty, "length(l) == 0")
    end

    test "length(l) == 3" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) == 3")
    end

    test "length(l) == 5" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) == 5")
    end

    test "length(l) != 0" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) != 0")
    end

    test "length(l) != 2" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) != 2")
    end
  end

  # ── flags at-least-N ───────────────────────────────────────────

  describe "flags at-least-N" do
    test "length(l) > 0" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) > 0")
    end

    test "length(l) >= 2" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) >= 2")
    end

    test "length(l) > 3" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) > 3")
    end

    test "length(l) >= 5" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) >= 5")
    end
  end

  # ── flags fewer-than-N ─────────────────────────────────────────

  describe "flags fewer-than-N" do
    test "length(l) < 1" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) < 1")
    end

    test "length(l) < 2" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) < 2")
    end

    test "length(l) <= 3" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) <= 3")
    end

    test "length(l) < 5" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "length(l) < 5")
    end
  end

  # ── flags reversed operands ────────────────────────────────────

  describe "flags reversed operands" do
    test "0 == length(l)" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "0 == length(l)")
    end

    test "2 <= length(l)" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "2 <= length(l)")
    end

    test "0 < length(l)" do
      assert [%Issue{}] =
               check(NoLengthComparisonForEmpty, "0 < length(l)")
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "length(l) == 6 (above max)" do
      assert check(NoLengthComparisonForEmpty, "length(l) == 6") == []
    end

    test "length(l) > 5 (would need 6 underscores)" do
      assert check(NoLengthComparisonForEmpty, "length(l) > 5") == []
    end

    test "length(l) >= 6" do
      assert check(NoLengthComparisonForEmpty, "length(l) >= 6") == []
    end

    test "list == [] (already fixed form)" do
      assert check(NoLengthComparisonForEmpty, "l == []") == []
    end

    test "match? pattern (already fixed form)" do
      assert check(NoLengthComparisonForEmpty, "match?([_, _ | _], l)") == []
    end

    test "length in arithmetic (not a comparison)" do
      assert check(NoLengthComparisonForEmpty, "length(l) + 1") == []
    end

    test "multiple violations in one module" do
      code = """
      defmodule E do
        def f(l), do: length(l) == 0
        def g(l), do: length(l) > 3
      end
      """

      assert length(check(NoLengthComparisonForEmpty, code)) == 2
    end
  end

  # ── does NOT flag comparisons inside guards ─────────────────────

  describe "does NOT flag comparisons inside guards" do
    test "length(l) >= 3 in function guard" do
      code = """
      defmodule M do
        def f(l) when length(l) >= 3, do: :ok
      end
      """

      assert check(NoLengthComparisonForEmpty, code) == []
    end

    test "length(l) == 0 in function guard" do
      code = """
      defmodule M do
        def f(l) when length(l) == 0, do: :ok
      end
      """

      assert check(NoLengthComparisonForEmpty, code) == []
    end

    test "length(l) > 2 in case guard" do
      code = """
      defmodule M do
        def f(l) do
          case l do
            x when length(x) > 2 -> :ok
            _ -> :error
          end
        end
      end
      """

      assert check(NoLengthComparisonForEmpty, code) == []
    end
  end

  # ── does NOT flag non-variable args (regression) ───────────────

  describe "does NOT flag non-variable arguments (regression)" do
    test "length(&1) > 1 (capture arg)" do
      assert check(NoLengthComparisonForEmpty, "Enum.filter(groups, &(length(&1) > 1))") == []
    end

    test "length(hd(x)) == 0 (call arg)" do
      assert check(NoLengthComparisonForEmpty, "length(hd(x)) == 0") == []
    end

    test "length(Map.get(m, k)) > 0 (dot-call arg)" do
      assert check(NoLengthComparisonForEmpty, "length(Map.get(m, k)) > 0") == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "meta.line is set" do
      [issue] =
        check(NoLengthComparisonForEmpty, "length(l) == 0")

      assert issue.meta.line != nil
    end
  end
end
