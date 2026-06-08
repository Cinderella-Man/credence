defmodule Credence.Pattern.NoListFoldFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListFold

  describe "fix foldl" do
    test "replaces direct List.foldl with Enum.reduce" do
      input = """
      List.foldl(list, 0, fn x, acc -> acc + x end)
      """

      expected = """
      Enum.reduce(list, 0, fn x, acc -> acc + x end)
      """

      assert fix(NoListFold, input) == expected
    end

    test "replaces piped List.foldl with Enum.reduce" do
      input = """
      list |> List.foldl(0, fn x, acc -> acc + x end)
      """

      expected = """
      list |> Enum.reduce(0, fn x, acc -> acc + x end)
      """

      assert fix(NoListFold, input) == expected
    end
  end

  describe "fix foldr" do
    test "replaces direct List.foldr with Enum.reverse + Enum.reduce" do
      input = """
      List.foldr(list, [], fn x, acc -> [x | acc] end)
      """

      expected = """
      Enum.reduce(Enum.reverse(list), [], fn x, acc -> [x | acc] end)
      """

      assert fix(NoListFold, input) == expected
    end

    test "replaces piped List.foldr with Enum.reverse + Enum.reduce" do
      input = """
      list |> List.foldr([], fn x, acc -> [x | acc] end)
      """

      expected = """
      list |> Enum.reverse() |> Enum.reduce([], fn x, acc -> [x | acc] end)
      """

      assert fix(NoListFold, input) == expected
    end
  end

  describe "fix preserves" do
    test "does not modify Enum.reduce" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> acc + x end)
      """

      assert fix(NoListFold, code) == code
    end

    test "preserves surrounding code" do
      input = """
      defmodule M do
        def run(list) do
          sum = List.foldl(list, 0, fn x, acc -> acc + x end)
          sum * 2
        end
      end
      """

      expected = """
      defmodule M do
        def run(list) do
          sum = Enum.reduce(list, 0, fn x, acc -> acc + x end)
          sum * 2
        end
      end
      """

      assert fix(NoListFold, input) == expected
    end
  end

  describe "fix round-trip" do
    test "fixed foldl produces no issues" do
      code = """
      List.foldl(list, 0, fn x, acc -> acc + x end)
      """

      assert check(NoListFold, fix(NoListFold, code)) == []
    end

    test "fixed foldr produces no issues" do
      code = """
      List.foldr(list, [], fn x, acc -> [x | acc] end)
      """

      assert check(NoListFold, fix(NoListFold, code)) == []
    end
  end
end
