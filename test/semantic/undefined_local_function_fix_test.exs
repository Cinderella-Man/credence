defmodule Credence.Semantic.UndefinedLocalFunctionFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedLocalFunction

  defp fix(source, message, line \\ 1) do
    UndefinedLocalFunction.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  @infinity_msg "undefined function infinity/0 (expected MyModule to define such a function or for it to be imported, but none are available)"

  describe "infinity() → :math.inf()" do
    test "standalone call" do
      assert fix("infinity()", @infinity_msg) == ":math.inf()"
    end

    test "negated" do
      assert fix("-infinity()", @infinity_msg) == "-:math.inf()"
    end

    test "in a tuple" do
      assert fix("{-infinity(), -infinity()}", @infinity_msg) ==
               "{-:math.inf(), -:math.inf()}"
    end

    test "in Enum.reduce accumulator" do
      input = "Enum.reduce(nums, {-infinity(), -infinity()}, fn x, acc -> x end)"

      assert fix(input, @infinity_msg) ==
               "Enum.reduce(nums, {-:math.inf(), -:math.inf()}, fn x, acc -> x end)"
    end

    test "only on reported line" do
      input = "x = infinity()\ny = infinity()"

      assert fix(input, @infinity_msg, 2) ==
               "x = infinity()\ny = :math.inf()"
    end
  end

  describe "no-ops" do
    test "unknown local function unchanged" do
      source = "foobar()"
      msg = "undefined function foobar/0 (expected MyModule to define such a function)"
      assert fix(source, msg) == source
    end
  end
end
