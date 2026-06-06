defmodule Credence.Pattern.NoSortForTopKFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoSortForTopK

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoSortForTopK, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "sort |> take(1) → Enum.min" do
      input = """
      Enum.sort(list) |> Enum.take(1)
      """

      expected = """
      Enum.min(list)
      """

      assert fix(input) == expected
    end

    test "sort |> hd() → Enum.min" do
      input = """
      Enum.sort(list) |> hd()
      """

      expected = """
      Enum.min(list)
      """

      assert fix(input) == expected
    end

    test "sort |> Enum.at(0) → Enum.min" do
      input = """
      Enum.sort(list) |> Enum.at(0)
      """

      expected = """
      Enum.min(list)
      """

      assert fix(input) == expected
    end

    test "sort |> reverse |> take(1) → Enum.max" do
      input = """
      Enum.sort(list) |> Enum.reverse() |> Enum.take(1)
      """

      expected = """
      Enum.max(list)
      """

      assert fix(input) == expected
    end

    test "sort |> reverse |> hd() → Enum.max" do
      input = """
      Enum.sort(list) |> Enum.reverse() |> hd()
      """

      expected = """
      Enum.max(list)
      """

      assert fix(input) == expected
    end

    test "sort |> reverse |> Enum.at(0) → Enum.max" do
      input = """
      Enum.sort(list) |> Enum.reverse() |> Enum.at(0)
      """

      expected = """
      Enum.max(list)
      """

      assert fix(input) == expected
    end

    test "sort |> reverse |> reverse |> take(1) → Enum.min (double reverse is no-op)" do
      input = """
      Enum.sort(list) |> Enum.reverse() |> Enum.reverse() |> Enum.take(1)
      """

      expected = """
      Enum.min(list)
      """

      assert fix(input) == expected
    end

    test "fixes pattern inside function body" do
      input = """
      defmodule Example do
        def f(list), do: Enum.sort(list) |> Enum.take(1)
      end
      """

      expected = """
      defmodule Example do
        def f(list), do: Enum.min(list)
      end
      """

      assert fix(input) == expected
    end

    test "fixes pattern inside Enum.map" do
      input = """
      Enum.map(lists, fn l -> Enum.sort(l) |> Enum.take(1) end)
      """

      expected = """
      Enum.map(lists, fn l -> Enum.min(l) end)
      """

      assert fix(input) == expected
    end

    test "fixes multiple occurrences" do
      input = """
      defmodule Example do
        def f(a, b) do
          x = Enum.sort(a) |> Enum.take(1)
          y = Enum.sort(b) |> Enum.reverse() |> Enum.at(0)
          {x, y}
        end
      end
      """

      expected = """
      defmodule Example do
        def f(a, b) do
          x = Enum.min(a)
          y = Enum.max(b)
          {x, y}
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes sort |> take(1) in assignment" do
      input = """
      result = Enum.sort(list) |> Enum.take(1)
      """

      expected = """
      result = Enum.min(list)
      """

      assert fix(input) == expected
    end

    test "does not change non-fixable patterns" do
      code = """
      Enum.sort(list) |> Enum.take(2)
      """

      assert fix(code) == code
    end

    test "does not change sort |> take(1) followed by more steps" do
      code = """
      Enum.sort(list) |> Enum.take(1) |> length()
      """

      assert fix(code) == code
    end

    test "does not change code without fixable patterns" do
      code = """
      defmodule Example do
        def f(list), do: Enum.min(list)
      end
      """

      assert fix(code) == code
    end
  end
end
