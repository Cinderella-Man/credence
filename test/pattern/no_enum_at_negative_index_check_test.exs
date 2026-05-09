defmodule Credence.Pattern.NoEnumAtNegativeIndexCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoEnumAtNegativeIndex.check(ast, [])
  end

  describe "flags negative literal indices" do
    test "Enum.at(list, -1)" do
      code = "defmodule M do\n  def f(list), do: Enum.at(list, -1)\nend"
      assert [%Issue{rule: :no_enum_at_negative_index}] = check(code)
    end

    test "Enum.at(list, -2)" do
      code = "defmodule M do\n  def f(list), do: Enum.at(list, -2)\nend"
      assert [%Issue{rule: :no_enum_at_negative_index}] = check(code)
    end

    test "Enum.at(list, -3)" do
      code = "defmodule M do\n  def f(list), do: Enum.at(list, -3)\nend"
      assert [%Issue{rule: :no_enum_at_negative_index}] = check(code)
    end

    test "piped form" do
      code = "defmodule M do\n  def f(list), do: list |> Enum.sort() |> Enum.at(-1)\nend"
      assert [%Issue{rule: :no_enum_at_negative_index}] = check(code)
    end

    test "multiple on same list" do
      code =
        "defmodule M do\n  def f(s) do\n    a = Enum.at(s, -1)\n    b = Enum.at(s, -2)\n    {a, b}\n  end\nend"

      assert length(check(code)) == 2
    end

    test "inside if block" do
      code = "defmodule M do\n  def f(list) do\n    if true, do: Enum.at(list, -1)\n  end\nend"
      assert length(check(code)) == 1
    end

    test "in expression context (not assignment)" do
      code = "defmodule M do\n  def f(s), do: Enum.at(s, -1) * Enum.at(s, -2)\nend"
      assert length(check(code)) == 2
    end
  end

  describe "does NOT flag" do
    test "positive index" do
      assert check("defmodule M do\n  def f(l), do: Enum.at(l, 0)\nend") == []
    end

    test "positive index 5" do
      assert check("defmodule M do\n  def f(l), do: Enum.at(l, 5)\nend") == []
    end

    test "variable index" do
      assert check("defmodule M do\n  def f(l, i), do: Enum.at(l, i)\nend") == []
    end

    test "expression index" do
      assert check("defmodule M do\n  def f(l, n), do: Enum.at(l, n - 1)\nend") == []
    end

    test "List.last" do
      assert check("defmodule M do\n  def f(l), do: List.last(l)\nend") == []
    end

    test "unrelated Enum call" do
      assert check("defmodule M do\n  def f(l), do: Enum.reverse(l)\nend") == []
    end
  end
end
