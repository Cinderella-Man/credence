defmodule Credence.Pattern.NoFilterThenFirstFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoFilterThenFirst

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoFilterThenFirst, code, [])
  end

  # ── Pipeline form (Stream.filter) ──────────────────────────────────────

  describe "pipeline fix" do
    test "Stream.filter(coll, pred) |> Enum.at(0) → Enum.find(coll, pred)" do
      assert fix("Stream.filter(nums, &even?/1) |> Enum.at(0)") ==
               "Enum.find(nums, &even?/1)"
    end

    test "inside longer pipeline" do
      input = """
      defmodule M do
        def first_palindrome(n) do
          (n + 1)
          |> Stream.iterate(&(&1 + 1))
          |> Stream.filter(&palindrome?/1)
          |> Enum.at(0)
        end
      end
      """

      expected = """
      defmodule M do
        def first_palindrome(n) do
          (n + 1) |> Stream.iterate(&(&1 + 1)) |> Enum.find(&palindrome?/1)
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ── Nested form (Stream.filter) ────────────────────────────────────────

  describe "nested fix" do
    test "Enum.at(Stream.filter(coll, pred), 0) → Enum.find(coll, pred)" do
      assert fix("Enum.at(Stream.filter(nums, &even?/1), 0)") ==
               "Enum.find(nums, &even?/1)"
    end
  end

  # ── Non-fixable: eager Enum.filter left untouched ──────────────────────
  #
  # Enum.filter evaluates `pred` on every element; rewriting to Enum.find
  # (which stops at the first match) would change behaviour for side-effecting
  # or raising predicates. These must remain unchanged.

  describe "leaves eager Enum.filter unchanged" do
    test "leaves Enum.filter |> Enum.at(0) unchanged" do
      code = "Enum.filter(nums, &even?/1) |> Enum.at(0)"
      assert fix(code) == code
    end

    test "leaves nested Enum.at(Enum.filter(...), 0) unchanged" do
      code = "Enum.at(Enum.filter(nums, &even?/1), 0)"
      assert fix(code) == code
    end
  end

  # ── Non-fixable: other non-matching patterns ───────────────────────────

  describe "does not fix non-matching patterns" do
    test "leaves Stream.filter |> Enum.at(1) unchanged" do
      code = "Stream.filter(nums, &even?/1) |> Enum.at(1)"
      assert fix(code) == code
    end

    test "leaves Enum.find unchanged" do
      code = "Enum.find(nums, &even?/1)"
      assert fix(code) == code
    end
  end
end
