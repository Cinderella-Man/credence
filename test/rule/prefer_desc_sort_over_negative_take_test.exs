defmodule Credence.Pattern.PreferDescSortOverNegativeTakeTest do
  use ExUnit.Case
  alias Credence.Pattern.PreferDescSortOverNegativeTake

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    PreferDescSortOverNegativeTake.check(ast, [])
  end

  defp fix(code), do: PreferDescSortOverNegativeTake.fix(code, [])

  # ── check ───────────────────────────────────────────────────────

  describe "check" do
    test "flags Enum.sort() |> Enum.take(-n) pipeline" do
      code = """
      nums
      |> Enum.sort()
      |> Enum.take(-3)
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags Enum.sort(list) |> Enum.take(-n) direct call form" do
      code = """
      Enum.sort(nums) |> Enum.take(-3)
      """

      assert length(check(code)) == 1
    end

    test "flags inside a defmodule" do
      code = """
      defmodule Example do
        def run(nums) do
          nums
          |> Enum.sort()
          |> Enum.take(-5)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags with longer pipeline before sort" do
      code = """
      nums
      |> Enum.map(&(&1 * 2))
      |> Enum.sort()
      |> Enum.take(-3)
      """

      assert length(check(code)) == 1
    end

    test "does not flag Enum.sort(:desc) |> Enum.take(n)" do
      assert check("nums |> Enum.sort(:desc) |> Enum.take(3)") == []
    end

    test "does not flag Enum.sort() |> Enum.take(positive n)" do
      assert check("nums |> Enum.sort() |> Enum.take(3)") == []
    end

    test "does not flag Enum.sort(comparator) |> Enum.take(-n)" do
      assert check("nums |> Enum.sort(&(&1 >= &2)) |> Enum.take(-3)") == []
    end

    test "does not flag unrelated Enum.sort()" do
      assert check("nums |> Enum.sort() |> Enum.map(&(&1 * 2))") == []
    end

    test "does not flag standalone Enum.take(-n)" do
      assert check("nums |> Enum.take(-3)") == []
    end
  end

  # ── fix ─────────────────────────────────────────────────────────

  describe "fix" do
    test "transforms piped pipeline" do
      result = fix("nums\n|> Enum.sort()\n|> Enum.take(-3)\n")
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(3)"
      refute result =~ "Enum.take(-3)"
    end

    test "transforms direct Enum.sort(list) |> Enum.take(-n)" do
      code = """
      defmodule Example do
        def run(nums) do
          Enum.sort(nums) |> Enum.take(-3)
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.sort(nums, :desc)"
      assert result =~ "Enum.take(3)"
      refute result =~ "Enum.take(-3)"
    end

    test "transforms inside a defmodule" do
      code = """
      defmodule Example do
        def run(nums) do
          nums
          |> Enum.sort()
          |> Enum.take(-5)
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(5)"
    end

    test "transforms with longer pipeline before sort" do
      code = """
      nums
      |> Enum.map(&(&1 * 2))
      |> Enum.sort()
      |> Enum.take(-3)
      """

      result = fix(code)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(3)"
    end

    test "transforms multiple independent pipelines" do
      code = """
      defmodule Example do
        def a(nums), do: nums |> Enum.sort() |> Enum.take(-3)
        def b(nums), do: nums |> Enum.sort() |> Enum.take(-5)
      end
      """

      result = fix(code)
      assert result =~ "Enum.take(3)"
      assert result =~ "Enum.take(5)"
      refute result =~ "Enum.take(-3)"
      refute result =~ "Enum.take(-5)"
    end

    test "does not modify already correct code" do
      code = "nums |> Enum.sort(:desc) |> Enum.take(3)\n"
      result = fix(code)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(3)"
    end

    test "does not modify positive take" do
      code = "nums |> Enum.sort() |> Enum.take(3)\n"
      result = fix(code)
      assert result =~ "Enum.sort()"
      assert result =~ "Enum.take(3)"
    end

    test "does not modify when sort has comparator" do
      code = "nums |> Enum.sort(&(&1 >= &2)) |> Enum.take(-3)\n"
      result = fix(code)
      assert result =~ "Enum.take(-3)"
    end

    test "does not modify when sort and take are not adjacent" do
      code = """
      nums
      |> Enum.sort()
      |> Enum.filter(&(&1 > 0))
      |> Enum.take(-3)
      """

      result = fix(code)
      assert result =~ "Enum.sort()"
      assert result =~ "Enum.take(-3)"
    end

    test "produces valid Elixir code" do
      code = """
      defmodule TestFix do
        def run(nums) do
          nums
          |> Enum.sort()
          |> Enum.take(-3)
        end
      end
      """

      result = fix(code)
      assert {:ok, _} = Code.string_to_quoted(result)
    end

    test "produces valid Elixir code for direct form" do
      code = """
      defmodule TestFix do
        def run(nums) do
          Enum.sort(nums) |> Enum.take(-3)
        end
      end
      """

      result = fix(code)
      assert {:ok, _} = Code.string_to_quoted(result)
    end
  end
end
