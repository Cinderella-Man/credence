defmodule Credence.Semantic.UndefinedFunction.NegateArgFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  @msg "Enum.take_last/2 is undefined or private"

  describe "Enum.take_last(list, n) → Enum.take(list, -n)" do
    test "with literal integer" do
      assert fix("Enum.take_last(items, 3)", @msg) == "Enum.take(items, -3)"
    end

    test "with variable" do
      assert fix("Enum.take_last(items, n)", @msg) == "Enum.take(items, -n)"
    end

    test "in assignment" do
      assert fix("last_few = Enum.take_last(list, 5)", @msg) == "last_few = Enum.take(list, -5)"
    end

    test "piped" do
      assert fix("items |> Enum.take_last(2)", @msg) == "items |> Enum.take(-2)"
    end

    test "with function call as count" do
      assert fix("Enum.take_last(items, length(subset))", @msg) ==
               "Enum.take(items, -(length(subset)))"
    end

    test "with arithmetic expression as count" do
      assert fix("Enum.take_last(items, n + 1)", @msg) == "Enum.take(items, -(n + 1))"
    end

    test "first arg is complex expression" do
      assert fix("Enum.take_last(Enum.sort(items), 3)", @msg) ==
               "Enum.take(Enum.sort(items), -3)"
    end

    test "only on reported line" do
      input = "a = Enum.take(xs, 3)\nb = Enum.take_last(xs, 2)\nc = Enum.drop(xs, 1)"

      assert fix(input, @msg, 2) ==
               "a = Enum.take(xs, 3)\nb = Enum.take(xs, -2)\nc = Enum.drop(xs, 1)"
    end

    test "bare variable count — no parens needed" do
      assert fix("Enum.take_last(list, count)", @msg) == "Enum.take(list, -count)"
    end

    test "bare integer count — no parens needed" do
      assert fix("Enum.take_last(list, 10)", @msg) == "Enum.take(list, -10)"
    end
  end
end
