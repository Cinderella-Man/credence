defmodule Credence.Pattern.NoSortThenReverseFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.NoSortThenReverse.fix(code, [])
  end

  # ── Atom direction: pipeline form ───────────────────────────────────────

  describe "pipeline – atom direction" do
    test "default asc → :desc" do
      assert fix("x |> Enum.sort() |> Enum.reverse()") == "x |> Enum.sort(:desc)"
    end

    test "explicit :asc → :desc" do
      assert fix("x |> Enum.sort(:asc) |> Enum.reverse()") == "x |> Enum.sort(:desc)"
    end

    test ":desc → removes direction (default asc)" do
      assert fix("x |> Enum.sort(:desc) |> Enum.reverse()") == "x |> Enum.sort()"
    end

    test "direct call piped to reverse" do
      assert fix("Enum.sort(nums) |> Enum.reverse()") == "Enum.sort(nums, :desc)"
    end

    test "direct call :asc piped to reverse" do
      assert fix("Enum.sort(nums, :asc) |> Enum.reverse()") == "Enum.sort(nums, :desc)"
    end

    test "direct call :desc piped to reverse" do
      assert fix("Enum.sort(nums, :desc) |> Enum.reverse()") == "Enum.sort(nums)"
    end
  end

  # ── Atom direction: nested form ─────────────────────────────────────────

  describe "nested – atom direction" do
    test "default asc → :desc" do
      assert fix("Enum.reverse(Enum.sort(nums))") == "Enum.sort(nums, :desc)"
    end

    test "explicit :asc → :desc" do
      assert fix("Enum.reverse(Enum.sort(nums, :asc))") == "Enum.sort(nums, :desc)"
    end

    test ":desc → ascending" do
      assert fix("Enum.reverse(Enum.sort(nums, :desc))") == "Enum.sort(nums)"
    end
  end

  # ── Function captures ───────────────────────────────────────────────────

  describe "pipeline – function captures" do
    test "&>=/2 (desc) → ascending" do
      assert fix("Enum.sort(nums, &>=/2) |> Enum.reverse()") == "Enum.sort(nums)"
    end

    test "&<=/2 (asc) → :desc" do
      assert fix("Enum.sort(nums, &<=/2) |> Enum.reverse()") == "Enum.sort(nums, :desc)"
    end
  end

  describe "nested – function captures" do
    test "&>=/2 (desc) → ascending" do
      assert fix("Enum.reverse(Enum.sort(nums, &>=/2))") == "Enum.sort(nums)"
    end

    test "&<=/2 (asc) → :desc" do
      assert fix("Enum.reverse(Enum.sort(nums, &<=/2))") == "Enum.sort(nums, :desc)"
    end
  end

  # ── Anonymous comparators ───────────────────────────────────────────────

  describe "pipeline – anonymous comparators" do
    test "fn a, b -> a > b end (desc) → ascending" do
      assert fix("Enum.sort(nums, fn a, b -> a > b end) |> Enum.reverse()") == "Enum.sort(nums)"
    end

    test "fn a, b -> a < b end (asc) → :desc" do
      assert fix("Enum.sort(nums, fn a, b -> a < b end) |> Enum.reverse()") ==
               "Enum.sort(nums, :desc)"
    end

    test "fn a, b -> b < a end (desc, flipped) → ascending" do
      assert fix("Enum.sort(nums, fn a, b -> b < a end) |> Enum.reverse()") == "Enum.sort(nums)"
    end

    test "fn a, b -> b > a end (asc, flipped) → :desc" do
      assert fix("Enum.sort(nums, fn a, b -> b > a end) |> Enum.reverse()") ==
               "Enum.sort(nums, :desc)"
    end
  end

  describe "nested – anonymous comparators" do
    test "fn a, b -> a > b end (desc) → ascending" do
      assert fix("Enum.reverse(Enum.sort(nums, fn a, b -> a > b end))") == "Enum.sort(nums)"
    end
  end

  # ── No-ops ──────────────────────────────────────────────────────────────

  describe "no-ops" do
    test "variable direction unchanged" do
      code = "Enum.sort(nums, dir) |> Enum.reverse()"
      assert fix(code) == code
    end

    test "opaque comparator unchanged" do
      code = "Enum.sort(nums, &MyModule.compare/2) |> Enum.reverse()"
      assert fix(code) == code
    end

    test "reverse without preceding sort unchanged" do
      code = "Enum.reverse(nums)"
      assert fix(code) == code
    end
  end
end
