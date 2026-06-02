defmodule Credence.Pattern.NoReverseThenSortFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoReverseThenSort

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoReverseThenSort, code, [])
  end

  # ── Pipeline form ────────────────────────────────────────────────────────

  describe "pipeline fixes" do
    test "reverse then sort → sort" do
      assert fix("x |> Enum.reverse() |> Enum.sort()") == "x |> Enum.sort()"
    end

    test "multi-step before reverse" do
      assert fix("x |> Enum.filter(&(&1 > 0)) |> Enum.reverse() |> Enum.sort()") ==
               "x |> Enum.filter(&(&1 > 0)) |> Enum.sort()"
    end
  end

  # ── Direct call piped to sort ────────────────────────────────────────────

  describe "direct call piped to sort" do
    test "Enum.reverse(x) |> Enum.sort() → Enum.sort(x)" do
      assert fix("Enum.reverse(x) |> Enum.sort()") == "Enum.sort(x)"
    end
  end

  # ── Nested call ──────────────────────────────────────────────────────────

  describe "nested call fixes" do
    test "Enum.sort(Enum.reverse(x)) → Enum.sort(x)" do
      assert fix("Enum.sort(Enum.reverse(x))") == "Enum.sort(x)"
    end
  end
end
