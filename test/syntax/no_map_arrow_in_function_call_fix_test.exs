defmodule Credence.Syntax.NoMapArrowInFunctionCallFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoMapArrowInFunctionCall

  defp analyze(code), do: NoMapArrowInFunctionCall.analyze(code)
  defp fix(code), do: NoMapArrowInFunctionCall.fix(code)

  test "fixes arrow syntax after empty map in Map.put" do
    input = "Map.put(%{}, key => value)"
    expected = "Map.put(%{}, key, value)"
    confirm_fix(fix(input), expected)
  end

  test "fixes multiline module with arrow in function call" do
    input = """
    defmodule Repro do
      def build_map(key, value) do
        Map.put(%{}, key => value)
      end
    end
    """

    expected = """
    defmodule Repro do
      def build_map(key, value) do
        Map.put(%{}, key, value)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes atom key arrow syntax" do
    confirm_fix(fix("Map.put(%{}, :key => value)"), "Map.put(%{}, :key, value)")
  end

  test "fixes string key arrow syntax" do
    confirm_fix(fix(~S'Map.put(%{}, "key" => value)'), ~S'Map.put(%{}, "key", value)')
  end

  test "fixed output no longer flags" do
    assert analyze(fix("Map.put(%{}, key => value)")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("Map.put(%{}, key => value)"))
  end

  test "fix does not mangle valid map syntax" do
    input = ~S'%{"key" => "val"}'
    confirm_fix(fix(input), input)
  end

  test "fix does not mangle valid three-arg Map.put" do
    input = "Map.put(%{}, :key, value)"
    confirm_fix(fix(input), input)
  end
end
