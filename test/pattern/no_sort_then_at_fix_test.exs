defmodule Credence.Pattern.NoSortThenAtFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoSortThenAt

  # ── Atom direction (existing) ───────────────────────────────────────────

  describe "pipeline form – atom direction" do
    test "Enum.sort(nums) |> Enum.at(0) → Enum.min(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums) |> Enum.at(0)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "Enum.sort(nums, :asc) |> Enum.at(0) → Enum.min(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, :asc) |> Enum.at(0)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "Enum.sort(nums, :desc) |> Enum.at(0) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, :desc) |> Enum.at(0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "Enum.sort(nums) |> Enum.at(-1) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums) |> Enum.at(-1)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "Enum.sort(nums, :asc) |> Enum.at(-1) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, :asc) |> Enum.at(-1)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "Enum.sort(nums, :desc) |> Enum.at(-1) → Enum.min(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, :desc) |> Enum.at(-1)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "inside def" do
      input = """
      defmodule M do
        def largest(nums) do
          Enum.sort(nums, :desc) |> Enum.at(0)
        end
      end
      """

      expected = """
      defmodule M do
        def largest(nums) do
          Enum.max(nums, fn -> nil end)
        end
      end
      """

      confirm_fix(fix(NoSortThenAt, input), expected)
    end
  end

  describe "nested form – atom direction" do
    test "Enum.at(Enum.sort(nums), 0) → Enum.min(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.at(Enum.sort(nums), 0)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "Enum.at(Enum.sort(nums, :desc), 0) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.at(Enum.sort(nums, :desc), 0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "Enum.at(Enum.sort(nums), -1) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.at(Enum.sort(nums), -1)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "Enum.at(Enum.sort(nums, :desc), -1) → Enum.min(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.at(Enum.sort(nums, :desc), -1)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "inside def" do
      input = """
      defmodule M do
        def smallest(nums) do
          Enum.at(Enum.sort(nums), 0)
        end
      end
      """

      expected = """
      defmodule M do
        def smallest(nums) do
          Enum.min(nums, fn -> nil end)
        end
      end
      """

      confirm_fix(fix(NoSortThenAt, input), expected)
    end
  end

  # ── Function captures ───────────────────────────────────────────────────

  describe "pipeline form – function captures" do
    test "Enum.sort(nums, &>=/2) |> Enum.at(0) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, &>=/2) |> Enum.at(0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "Enum.sort(nums, &>=/2) |> Enum.at(-1) → Enum.min(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, &>=/2) |> Enum.at(-1)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "Enum.sort(nums, &<=/2) |> Enum.at(0) → Enum.min(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, &<=/2) |> Enum.at(0)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "Enum.sort(nums, &<=/2) |> Enum.at(-1) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, &<=/2) |> Enum.at(-1)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end
  end

  describe "nested form – function captures" do
    test "Enum.at(Enum.sort(nums, &>=/2), 0) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.at(Enum.sort(nums, &>=/2), 0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "Enum.at(Enum.sort(nums, &<=/2), -1) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.at(Enum.sort(nums, &<=/2), -1)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end
  end

  # ── Anonymous comparators ───────────────────────────────────────────────

  describe "pipeline form – anonymous comparators" do
    test "fn a, b -> a > b end at(0) → Enum.max (desc + first)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> a > b end) |> Enum.at(0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "fn a, b -> a >= b end at(0) → Enum.max (desc + first)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> a >= b end) |> Enum.at(0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "fn a, b -> a < b end at(0) → Enum.min (asc + first)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> a < b end) |> Enum.at(0)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "fn a, b -> a <= b end at(0) → Enum.min (asc + first)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> a <= b end) |> Enum.at(0)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "fn a, b -> a > b end at(-1) → Enum.min (desc + last)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> a > b end) |> Enum.at(-1)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "fn a, b -> a < b end at(-1) → Enum.max (asc + last)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> a < b end) |> Enum.at(-1)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end
  end

  describe "pipeline form – flipped anonymous comparators" do
    test "fn a, b -> b < a end at(0) → Enum.max (desc + first)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> b < a end) |> Enum.at(0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "fn a, b -> b <= a end at(0) → Enum.max (desc + first)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> b <= a end) |> Enum.at(0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "fn a, b -> b > a end at(0) → Enum.min (asc + first)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> b > a end) |> Enum.at(0)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end

    test "fn a, b -> b >= a end at(0) → Enum.min (asc + first)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.sort(nums, fn a, b -> b >= a end) |> Enum.at(0)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end
  end

  describe "nested form – anonymous comparators" do
    test "Enum.at(Enum.sort(fn a, b -> a > b end), 0) → Enum.max(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.at(Enum.sort(nums, fn a, b -> a > b end), 0)"),
        "Enum.max(nums, fn -> nil end)"
      )
    end

    test "Enum.at(Enum.sort(fn a, b -> a > b end), -1) → Enum.min(nums, fn -> nil end)" do
      confirm_fix(
        fix(NoSortThenAt, "Enum.at(Enum.sort(nums, fn a, b -> a > b end), -1)"),
        "Enum.min(nums, fn -> nil end)"
      )
    end
  end

  # ── No-ops ──────────────────────────────────────────────────────────────

  describe "no-ops" do
    test "leaves variable index unchanged (pipeline)" do
      code = "Enum.sort(nums, :desc) |> Enum.at(k - 1)"

      confirm_fix(fix(NoSortThenAt, code), code)
    end

    test "leaves variable index unchanged (nested)" do
      code = "Enum.at(Enum.sort(nums), mid)"

      confirm_fix(fix(NoSortThenAt, code), code)
    end

    test "leaves other literal index unchanged (pipeline)" do
      code = "Enum.sort(nums) |> Enum.at(3)"

      confirm_fix(fix(NoSortThenAt, code), code)
    end

    test "leaves other literal index unchanged (nested)" do
      code = "Enum.at(Enum.sort(nums), 2)"

      confirm_fix(fix(NoSortThenAt, code), code)
    end

    test "leaves variable direction unchanged" do
      code = "Enum.sort(nums, dir) |> Enum.at(0)"

      confirm_fix(fix(NoSortThenAt, code), code)
    end

    test "leaves opaque comparator unchanged" do
      code = "Enum.sort(nums, &MyModule.compare/2) |> Enum.at(0)"

      confirm_fix(fix(NoSortThenAt, code), code)
    end
  end
end
