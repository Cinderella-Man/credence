defmodule Credence.Syntax.NoMapArrowInFunctionCallAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoMapArrowInFunctionCall

  defp analyze(code), do: NoMapArrowInFunctionCall.analyze(code)

  test "flags Map.put with arrow syntax after empty map" do
    assert [%Issue{rule: :no_map_arrow_in_function_call}] = analyze("Map.put(%{}, key => value)")
  end

  test "flags in multiline module context" do
    input = """
    defmodule Repro do
      def build_map(key, value) do
        Map.put(%{}, key => value)
      end
    end
    """

    assert [%Issue{rule: :no_map_arrow_in_function_call, meta: %{line: 3}}] = analyze(input)
  end

  test "flags atom key arrow syntax after empty map" do
    assert [%Issue{rule: :no_map_arrow_in_function_call}] = analyze("Map.put(%{}, :key => value)")
  end

  test "flags string key arrow syntax after empty map" do
    assert [%Issue{rule: :no_map_arrow_in_function_call}] =
             analyze(~S'Map.put(%{}, "key" => value)')
  end

  test "leaves valid map syntax alone" do
    assert analyze(~S'%{"key" => "val"}') == []
  end

  test "leaves valid three-arg Map.put alone" do
    assert analyze("Map.put(%{}, :key, value)") == []
  end

  test "leaves tuple brace arrow to other rule" do
    # This is handled by NoMapArrowSyntaxInTupleBrace, not our rule
    assert analyze(~S'{"key" => "val"}') == []
  end
end
