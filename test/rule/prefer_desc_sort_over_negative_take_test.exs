defmodule Credence.Rule.PreferDescSortOverNegativeTakeTest do
  use ExUnit.Case
  alias Credence.Rule.PreferDescSortOverNegativeTake

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

      assert Enum.any?(issues, fn issue ->
               String.contains?(issue.message, "Prefer `Enum.sort(nums, :desc)")
             end)
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

    test "flags inside Enum.map callback" do
      code = """
      Enum.map(list, fn x ->
        x
        |> Enum.sort()
        |> Enum.take(-3)
      end)
      """

      assert length(check(code)) == 1
    end

    test "does not flag Enum.sort(:desc) |> Enum.take(n)" do
      code = """
      nums
      |> Enum.sort(:desc)
      |> Enum.take(3)
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort() |> Enum.take(positive n)" do
      code = """
      nums
      |> Enum.sort()
      |> Enum.take(3)
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort(comparator) |> Enum.take(-n)" do
      code = """
      nums
      |> Enum.sort(&(&1 >= &2))
      |> Enum.take(-3)
      """

      assert check(code) == []
    end

    test "does not flag unrelated Enum.sort()" do
      code = """
      nums
      |> Enum.sort()
      |> Enum.map(&(&1 * 2))
      """

      assert check(code) == []
    end

    test "does not flag unrelated Enum.take(-n)" do
      code = """
      nums
      |> Enum.take(-3)
      """

      assert check(code) == []
    end
  end

  # ── fix ─────────────────────────────────────────────────────────

  describe "fix" do
    test "transforms simple pipeline" do
      before = """
      nums
      |> Enum.sort()
      |> Enum.take(-3)
      """

      result = fix(before)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(3)"
      refute result =~ "Enum.take(-3)"
    end

    test "transforms inside a defmodule" do
      before = """
      defmodule Example do
        def run(nums) do
          nums
          |> Enum.sort()
          |> Enum.take(-5)
        end
      end
      """

      result = fix(before)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(5)"
    end

    test "transforms with longer pipeline before sort" do
      before = """
      nums
      |> Enum.map(&(&1 * 2))
      |> Enum.sort()
      |> Enum.take(-3)
      """

      result = fix(before)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(3)"
    end

    test "transforms multiple independent pipelines" do
      before = """
      defmodule Example do
        def a(nums), do: nums |> Enum.sort() |> Enum.take(-3)
        def b(nums), do: nums |> Enum.sort() |> Enum.take(-5)
      end
      """

      result = fix(before)
      assert result =~ "Enum.take(3)"
      assert result =~ "Enum.take(5)"
      refute result =~ "Enum.take(-3)"
      refute result =~ "Enum.take(-5)"
    end

    test "transforms large negative value" do
      before = """
      nums
      |> Enum.sort()
      |> Enum.take(-100)
      """

      result = fix(before)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(100)"
    end

    test "transforms negative one" do
      before = """
      nums
      |> Enum.sort()
      |> Enum.take(-1)
      """

      result = fix(before)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(1)"
    end

    test "does not modify already correct code" do
      code = """
      nums
      |> Enum.sort(:desc)
      |> Enum.take(3)
      """

      result = fix(code)
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(3)"
    end

    test "does not modify positive take" do
      code = """
      nums
      |> Enum.sort()
      |> Enum.take(3)
      """

      result = fix(code)
      assert result =~ "Enum.sort()"
      assert result =~ "Enum.take(3)"
    end

    test "does not modify when sort has comparator" do
      code = """
      nums
      |> Enum.sort(&(&1 >= &2))
      |> Enum.take(-3)
      """

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

    test "check flags but fix skips non-adjacent sort and take" do
      code = """
      nums
      |> Enum.sort()
      |> Enum.filter(&(&1 > 0))
      |> Enum.take(-3)
      """

      assert length(check(code)) == 1

      result = fix(code)
      assert result =~ "Enum.sort()"
      assert result =~ "Enum.take(-3)"
    end

    test "produces valid Elixir code" do
      before = """
      defmodule TestFix do
        def run(nums) do
          nums
          |> Enum.sort()
          |> Enum.take(-3)
        end
      end
      """

      result = fix(before)
      assert {:ok, _} = Code.string_to_quoted(result)
    end

    test "preserves other pipeline steps" do
      before = """
      nums
      |> Enum.map(&(&1 * 2))
      |> Enum.sort()
      |> Enum.take(-3)
      """

      result = fix(before)
      assert result =~ "Enum.map"
      assert result =~ "Enum.sort(:desc)"
      assert result =~ "Enum.take(3)"
    end
  end
end
