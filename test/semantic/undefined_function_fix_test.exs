defmodule Credence.Semantic.UndefinedFunctionFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  describe "Enum.last → List.last" do
    test "direct call" do
      assert fix("Enum.last(list)", "Enum.last/1 is undefined or private") == "List.last(list)"
    end

    test "piped" do
      assert fix("list |> Enum.last()", "Enum.last/0 is undefined or private") ==
               "list |> List.last()"
    end

    test "only on reported line" do
      input = "Enum.at(x, 0)\nEnum.last(x)\nEnum.count(x)"

      assert fix(input, "Enum.last/1 is undefined or private", 2) ==
               "Enum.at(x, 0)\nList.last(x)\nEnum.count(x)"
    end
  end

  describe "List.reverse → Enum.reverse" do
    test "direct call" do
      assert fix("List.reverse(items)", "List.reverse/1 is undefined or private") ==
               "Enum.reverse(items)"
    end

    test "piped" do
      assert fix("items |> List.reverse()", "List.reverse/1 is undefined or private") ==
               "items |> Enum.reverse()"
    end

    test "mid-pipeline" do
      assert fix("nums |> Enum.sort() |> List.reverse() |> hd()",
               "List.reverse/1 is undefined or private") ==
               "nums |> Enum.sort() |> Enum.reverse() |> hd()"
    end
  end

  describe "no-ops" do
    test "unknown function unchanged" do
      source = "MyModule.foo(x)"
      assert fix(source, "MyModule.foo/1 is undefined or private") == source
    end
  end
end
