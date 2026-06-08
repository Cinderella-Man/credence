defmodule Credence.Pattern.PreferDescSortOverNegativeTakeCheckTest do
  use Credence.RuleCase, async: true
  alias Credence.Pattern.PreferDescSortOverNegativeTake

  describe "check" do
    test "flags Enum.sort() |> Enum.take(-n) pipeline" do
      code = """
      nums
      |> Enum.sort()
      |> Enum.take(-3)
      """

      issues = check(PreferDescSortOverNegativeTake, code)
      assert length(issues) == 1
    end

    test "flags Enum.sort(list) |> Enum.take(-n) direct call form" do
      code = """
      Enum.sort(nums) |> Enum.take(-3)
      """

      assert length(check(PreferDescSortOverNegativeTake, code)) == 1
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

      assert length(check(PreferDescSortOverNegativeTake, code)) == 1
    end

    test "flags with longer pipeline before sort" do
      code = """
      nums
      |> Enum.map(&(&1 * 2))
      |> Enum.sort()
      |> Enum.take(-3)
      """

      assert length(check(PreferDescSortOverNegativeTake, code)) == 1
    end

    test "does not flag Enum.sort(:desc) |> Enum.take(n)" do
      assert check(PreferDescSortOverNegativeTake, """
             nums |> Enum.sort(:desc) |> Enum.take(3)
             """) ==
               []
    end

    test "does not flag Enum.sort() |> Enum.take(positive n)" do
      assert check(PreferDescSortOverNegativeTake, """
             nums |> Enum.sort() |> Enum.take(3)
             """) == []
    end

    test "does not flag Enum.sort(comparator) |> Enum.take(-n)" do
      assert check(
               PreferDescSortOverNegativeTake,
               """
               nums |> Enum.sort(&(&1 >= &2)) |> Enum.take(-3)
               """
             ) == []
    end

    test "does not flag unrelated Enum.sort()" do
      assert check(PreferDescSortOverNegativeTake, """
             nums |> Enum.sort() |> Enum.map(&(&1 * 2))
             """) ==
               []
    end

    test "does not flag standalone Enum.take(-n)" do
      assert check(PreferDescSortOverNegativeTake, """
             nums |> Enum.take(-3)
             """) == []
    end
  end
end
