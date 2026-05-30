defmodule Credence.Pattern.NoRedundantSortComparatorCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoRedundantSortComparator

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRedundantSortComparator.check(ast, [])
  end

  # ── FLAGGED: list patterns with ascending < ─────────────────────────────

  describe "flags sort with lexicographic list comparator" do
    test "2-element list, < or" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn [a, b], [c, d] -> a < c or (a == c and b < d) end)\n" <>
          "end"

      assert [%Issue{rule: :no_redundant_sort_comparator}] = check(code)
    end

    test "2-element list, < ||" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn [a, b], [c, d] -> a < c || (a == c && b < d) end)\n" <>
          "end"

      assert [%Issue{rule: :no_redundant_sort_comparator}] = check(code)
    end

    test "2-element list, <= or" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn [a, b], [c, d] -> a <= c or (a == c and b <= d) end)\n" <>
          "end"

      assert [%Issue{rule: :no_redundant_sort_comparator}] = check(code)
    end

    test "pipeline form" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: x |> Enum.sort(fn [a, b], [c, d] -> a < c or (a == c and b < d) end)\n" <>
          "end"

      assert [%Issue{rule: :no_redundant_sort_comparator}] = check(code)
    end
  end

  # ── FLAGGED: tuple patterns with ascending comparator ───────────────────

  describe "flags sort with lexicographic tuple comparator" do
    test "2-element tuple, < or" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn {a, b}, {c, d} -> a < c or (a == c and b < d) end)\n" <>
          "end"

      assert [%Issue{rule: :no_redundant_sort_comparator}] = check(code)
    end
  end

  # ── FLAGGED: longer element patterns ────────────────────────────────────

  describe "flags 3-element lexicographic comparator" do
    test "3-element list, < or chain" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn [a, b, c], [d, e, f] -> " <>
          "a < d or (a == d and (b < e or (b == e and c < f))) end)\n" <>
          "end"

      assert [%Issue{rule: :no_redundant_sort_comparator}] = check(code)
    end
  end

  # ── NOT FLAGGED: no comparator ──────────────────────────────────────────

  describe "does NOT flag sort without comparator" do
    test "Enum.sort/1" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x)\nend"
      assert check(code) == []
    end

    test "Enum.sort/2 with atom direction" do
      code = "defmodule M do\n  def f(x), do: Enum.sort(x, :desc)\nend"
      assert check(code) == []
    end
  end

  # ── NOT FLAGGED: non-lexicographic comparators ──────────────────────────

  describe "does NOT flag non-lexicographic comparators" do
    test "simple comparator without destructuring" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn a, b -> a < b end)\n" <>
          "end"

      assert check(code) == []
    end

    test "single element list comparator" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn [a], [b] -> a < b end)\n" <>
          "end"

      assert check(code) == []
    end
  end

  # ── NOT FLAGGED: descending comparator ──────────────────────────────────

  describe "does NOT flag descending comparator" do
    test "descending > or" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn [a, b], [c, d] -> a > c or (a == c and b > d) end)\n" <>
          "end"

      assert check(code) == []
    end
  end

  # ── NOT FLAGGED: wrong structure ────────────────────────────────────────

  describe "does NOT flag malformed comparators" do
    test "mixed comparison directions" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn [a, b], [c, d] -> a < c or (a == c and b > d) end)\n" <>
          "end"

      assert check(code) == []
    end

    test "wrong equality variable" do
      code =
        "defmodule M do\n" <>
          "  def f(x), do: Enum.sort(x, fn [a, b], [c, d] -> a < c or (c == a and b < d) end)\n" <>
          "end"

      assert check(code) == []
    end
  end
end
