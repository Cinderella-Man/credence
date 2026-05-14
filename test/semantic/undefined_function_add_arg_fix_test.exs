defmodule Credence.Semantic.UndefinedFunction.AddArgFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  @msg "List.second/1 is undefined or private"

  describe "List.second(list) → Enum.at(list, 1)" do
    test "direct call with variable" do
      assert fix("List.second(items)", @msg) == "Enum.at(items, 1)"
    end

    test "direct call with literal list" do
      assert fix("List.second([1, 2, 3])", @msg) == "Enum.at([1, 2, 3], 1)"
    end

    test "in assignment" do
      assert fix("second = List.second(sorted)", @msg) == "second = Enum.at(sorted, 1)"
    end

    test "piped" do
      assert fix("items |> List.second()", @msg) == "items |> Enum.at(1)"
    end

    test "nested in expression" do
      assert fix("x = List.second(items) + List.first(items)", @msg) ==
               "x = Enum.at(items, 1) + List.first(items)"
    end

    test "with function call as argument" do
      assert fix("List.second(Enum.sort(items))", @msg) == "Enum.at(Enum.sort(items), 1)"
    end

    test "only on reported line" do
      input = "a = List.first(xs)\nb = List.second(xs)\nc = List.last(xs)"

      assert fix(input, @msg, 2) == "a = List.first(xs)\nb = Enum.at(xs, 1)\nc = List.last(xs)"
    end

    test "realistic context from LLM log" do
      input = "    option1 = List.last(sorted) * List.second(sorted) * Enum.at(sorted, -3)"

      expected = "    option1 = List.last(sorted) * Enum.at(sorted, 1) * Enum.at(sorted, -3)"

      assert fix(input, @msg) == expected
    end
  end
end
