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
      assert fix(
               "nums |> Enum.sort() |> List.reverse() |> hd()",
               "List.reverse/1 is undefined or private"
             ) ==
               "nums |> Enum.sort() |> Enum.reverse() |> hd()"
    end
  end

  describe "Enum.partition → Enum.split_with (deprecated)" do
    test "direct call" do
      assert fix(
               "Enum.partition(list, &is_integer/1)",
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead"
             ) == "Enum.split_with(list, &is_integer/1)"
    end

    test "piped" do
      assert fix(
               "list |> Enum.partition(fn {_v, i} -> Integer.is_even(i) end)",
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead"
             ) == "list |> Enum.split_with(fn {_v, i} -> Integer.is_even(i) end)"
    end

    test "only on reported line" do
      input = "x = Enum.map(list, &f/1)\n{a, b} = Enum.partition(list, &pred/1)"

      assert fix(input, "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead", 2) ==
               "x = Enum.map(list, &f/1)\n{a, b} = Enum.split_with(list, &pred/1)"
    end
  end

  describe "no-ops" do
    test "unknown function unchanged" do
      source = "MyModule.foo(x)"
      assert fix(source, "MyModule.foo/1 is undefined or private") == source
    end
  end
end
