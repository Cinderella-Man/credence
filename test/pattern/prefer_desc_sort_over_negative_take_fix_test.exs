defmodule Credence.Pattern.PreferDescSortOverNegativeTakeFixTest do
  use ExUnit.Case
  alias Credence.Pattern.PreferDescSortOverNegativeTake

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(PreferDescSortOverNegativeTake, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "transforms piped pipeline" do
      input = """
      nums
      |> Enum.sort()
      |> Enum.take(-3)
      """

      expected = """
      nums
      |> Enum.sort(:desc)
      |> Enum.take(3)
      |> Enum.reverse()
      """

      assert fix(input) == expected
    end

    test "transforms direct Enum.sort(list) |> Enum.take(-n)" do
      input = """
      defmodule Example do
        def run(nums) do
          Enum.sort(nums) |> Enum.take(-3)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3) |> Enum.reverse()
        end
      end
      """

      assert fix(input) == expected
    end

    test "transforms inside a defmodule" do
      input = """
      defmodule Example do
        def run(nums) do
          nums
          |> Enum.sort()
          |> Enum.take(-5)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(nums) do
          nums
          |> Enum.sort(:desc)
          |> Enum.take(5)
          |> Enum.reverse()
        end
      end
      """

      assert fix(input) == expected
    end

    test "transforms with longer pipeline before sort" do
      input = """
      nums
      |> Enum.map(&(&1 * 2))
      |> Enum.sort()
      |> Enum.take(-3)
      """

      expected = """
      nums
      |> Enum.map(&(&1 * 2))
      |> Enum.sort(:desc)
      |> Enum.take(3)
      |> Enum.reverse()
      """

      assert fix(input) == expected
    end

    test "transforms multiple independent pipelines" do
      input = """
      defmodule Example do
        def a(nums), do: nums |> Enum.sort() |> Enum.take(-3)
        def b(nums), do: nums |> Enum.sort() |> Enum.take(-5)
      end
      """

      expected = """
      defmodule Example do
        def a(nums), do: nums |> Enum.sort(:desc) |> Enum.take(3) |> Enum.reverse()
        def b(nums), do: nums |> Enum.sort(:desc) |> Enum.take(5) |> Enum.reverse()
      end
      """

      assert fix(input) == expected
    end

    test "does not modify already correct code" do
      code = """
      nums |> Enum.sort(:desc) |> Enum.take(3)
      """

      assert fix(code) == code
    end

    test "does not modify positive take" do
      code = """
      nums |> Enum.sort() |> Enum.take(3)
      """

      assert fix(code) == code
    end

    test "does not modify when sort has comparator" do
      code = """
      nums |> Enum.sort(&(&1 >= &2)) |> Enum.take(-3)
      """

      assert fix(code) == code
    end

    test "does not modify when sort and take are not adjacent" do
      code = """
      nums
      |> Enum.sort()
      |> Enum.filter(&(&1 > 0))
      |> Enum.take(-3)
      """

      assert fix(code) == code
    end

    test "produces valid Elixir code" do
      input = """
      defmodule TestFix do
        def run(nums) do
          nums
          |> Enum.sort()
          |> Enum.take(-3)
        end
      end
      """

      expected = """
      defmodule TestFix do
        def run(nums) do
          nums
          |> Enum.sort(:desc)
          |> Enum.take(3)
          |> Enum.reverse()
        end
      end
      """

      assert fix(input) == expected
    end

    test "produces valid Elixir code for direct form" do
      input = """
      defmodule TestFix do
        def run(nums) do
          Enum.sort(nums) |> Enum.take(-3)
        end
      end
      """

      expected = """
      defmodule TestFix do
        def run(nums) do
          Enum.sort(nums, :desc) |> Enum.take(3) |> Enum.reverse()
        end
      end
      """

      assert fix(input) == expected
    end
  end
end
