defmodule Credence.Pattern.NoSortThenAtFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.NoSortThenAt.fix(code, [])
  end

  describe "pipeline form" do
    test "Enum.sort(nums) |> Enum.at(0) → Enum.min(nums)" do
      assert fix("Enum.sort(nums) |> Enum.at(0)") == "Enum.min(nums)"
    end

    test "Enum.sort(nums, :asc) |> Enum.at(0) → Enum.min(nums)" do
      assert fix("Enum.sort(nums, :asc) |> Enum.at(0)") == "Enum.min(nums)"
    end

    test "Enum.sort(nums, :desc) |> Enum.at(0) → Enum.max(nums)" do
      assert fix("Enum.sort(nums, :desc) |> Enum.at(0)") == "Enum.max(nums)"
    end

    test "Enum.sort(nums) |> Enum.at(-1) → Enum.max(nums)" do
      assert fix("Enum.sort(nums) |> Enum.at(-1)") == "Enum.max(nums)"
    end

    test "Enum.sort(nums, :asc) |> Enum.at(-1) → Enum.max(nums)" do
      assert fix("Enum.sort(nums, :asc) |> Enum.at(-1)") == "Enum.max(nums)"
    end

    test "Enum.sort(nums, :desc) |> Enum.at(-1) → Enum.min(nums)" do
      assert fix("Enum.sort(nums, :desc) |> Enum.at(-1)") == "Enum.min(nums)"
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
          Enum.max(nums)
        end
      end
      """

      assert fix(input) == String.trim_trailing(expected, "\n")
    end
  end

  describe "nested form" do
    test "Enum.at(Enum.sort(nums), 0) → Enum.min(nums)" do
      assert fix("Enum.at(Enum.sort(nums), 0)") == "Enum.min(nums)"
    end

    test "Enum.at(Enum.sort(nums, :desc), 0) → Enum.max(nums)" do
      assert fix("Enum.at(Enum.sort(nums, :desc), 0)") == "Enum.max(nums)"
    end

    test "Enum.at(Enum.sort(nums), -1) → Enum.max(nums)" do
      assert fix("Enum.at(Enum.sort(nums), -1)") == "Enum.max(nums)"
    end

    test "Enum.at(Enum.sort(nums, :desc), -1) → Enum.min(nums)" do
      assert fix("Enum.at(Enum.sort(nums, :desc), -1)") == "Enum.min(nums)"
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
          Enum.min(nums)
        end
      end
      """

      assert fix(input) == String.trim_trailing(expected, "\n")
    end
  end

  describe "no-ops" do
    test "leaves variable index unchanged (pipeline)" do
      code = "Enum.sort(nums, :desc) |> Enum.at(k - 1)"
      assert fix(code) == code
    end

    test "leaves variable index unchanged (nested)" do
      code = "Enum.at(Enum.sort(nums), mid)"
      assert fix(code) == code
    end

    test "leaves other literal index unchanged (pipeline)" do
      code = "Enum.sort(nums) |> Enum.at(3)"
      assert fix(code) == code
    end

    test "leaves other literal index unchanged (nested)" do
      code = "Enum.at(Enum.sort(nums), 2)"
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
  end
end
