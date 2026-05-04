defmodule Credence.Rule.NoSortThenAtTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoSortThenAt.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoSortThenAt.fix(code, [])
  end

  # ───────────────────────── check/2 tests ─────────────────────────

  describe "check/2" do
    test "flags Enum.sort |> Enum.at pipeline" do
      code = """
      defmodule M do
        def kth(nums, k), do: Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags nested Enum.at(Enum.sort(...))" do
      code = """
      defmodule M do
        def median(nums), do: Enum.at(Enum.sort(nums), div(length(nums), 2))
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "does not flag plain Enum.at" do
      code = """
      defmodule M do
        def get(list, i), do: Enum.at(list, i)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.take" do
      code = """
      defmodule M do
        def top3(nums), do: Enum.sort(nums, :desc) |> Enum.take(3)
      end
      """

      assert check(code) == []
    end
  end

  # ───────────────────────── fix/2 tests ────────────────────────────

  describe "fix/2 – pipeline form" do
    test "Enum.sort(nums) |> Enum.at(0) → Enum.min(nums)" do
      before = "Enum.sort(nums) |> Enum.at(0)"
      assert fix(before) == "Enum.min(nums)"
    end

    test "Enum.sort(nums, :asc) |> Enum.at(0) → Enum.min(nums)" do
      before = "Enum.sort(nums, :asc) |> Enum.at(0)"
      assert fix(before) == "Enum.min(nums)"
    end

    test "Enum.sort(nums, :desc) |> Enum.at(0) → Enum.max(nums)" do
      before = "Enum.sort(nums, :desc) |> Enum.at(0)"
      assert fix(before) == "Enum.max(nums)"
    end

    test "Enum.sort(nums) |> Enum.at(-1) → Enum.max(nums)" do
      before = "Enum.sort(nums) |> Enum.at(-1)"
      assert fix(before) == "Enum.max(nums)"
    end

    test "Enum.sort(nums, :asc) |> Enum.at(-1) → Enum.max(nums)" do
      before = "Enum.sort(nums, :asc) |> Enum.at(-1)"
      assert fix(before) == "Enum.max(nums)"
    end

    test "Enum.sort(nums, :desc) |> Enum.at(-1) → Enum.min(nums)" do
      before = "Enum.sort(nums, :desc) |> Enum.at(-1)"
      assert fix(before) == "Enum.min(nums)"
    end

    test "leaves variable index unchanged" do
      code = "Enum.sort(nums, :desc) |> Enum.at(k - 1)"
      assert fix(code) == code
    end

    test "leaves unknown direction unchanged" do
      code = "Enum.sort(nums, dir) |> Enum.at(0)"
      assert fix(code) == code
    end

    test "leaves custom comparator unchanged" do
      code = "Enum.sort(nums, fn a, b -> a > b end) |> Enum.at(0)"
      assert fix(code) == code
    end

    test "inside def – replaces correctly" do
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
          Enum.max(nums)
        end
      end
      """

      assert fix(input) == String.trim_trailing(expected, "\n")
    end
  end

  describe "fix/2 – nested form" do
    test "Enum.at(Enum.sort(nums), 0) → Enum.min(nums)" do
      before = "Enum.at(Enum.sort(nums), 0)"
      assert fix(before) == "Enum.min(nums)"
    end

    test "Enum.at(Enum.sort(nums, :desc), 0) → Enum.max(nums)" do
      before = "Enum.at(Enum.sort(nums, :desc), 0)"
      assert fix(before) == "Enum.max(nums)"
    end

    test "Enum.at(Enum.sort(nums), -1) → Enum.max(nums)" do
      before = "Enum.at(Enum.sort(nums), -1)"
      assert fix(before) == "Enum.max(nums)"
    end

    test "Enum.at(Enum.sort(nums, :desc), -1) → Enum.min(nums)" do
      before = "Enum.at(Enum.sort(nums, :desc), -1)"
      assert fix(before) == "Enum.min(nums)"
    end

    test "inside def – replaces correctly" do
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
          Enum.min(nums)
        end
      end
      """

      assert fix(input) == String.trim_trailing(expected, "\n")
    end

    test "leaves variable index unchanged" do
      code = "Enum.at(Enum.sort(nums), mid)"
      assert fix(code) == code
    end
  end
end
