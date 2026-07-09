defmodule Credence.Syntax.NoNestedCaptureAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoNestedCapture

  defp analyze(code), do: NoNestedCapture.analyze(code)

  test "flags nested capture inside a capture call" do
    assert [%Issue{rule: :no_nested_capture}] = analyze("&Map.update(&1, 0, &(&1 + 1))")
  end

  test "flags nested capture in multiline module" do
    code = """
    defmodule WorkStealQueue do
      def run do
        &Map.update(&1, 0, &(&1 + 1))
      end
    end
    """

    assert [%Issue{rule: :no_nested_capture}] = analyze(code)
  end

  test "flags nested capture with multiple capture vars" do
    assert [%Issue{rule: :no_nested_capture}] = analyze("&Enum.reduce(&1, 0, &(&1 + &2))")
  end

  test "leaves simple capture without nesting alone" do
    assert analyze("&Map.update(&1, 0, fn x -> x + 1 end)") == []
  end

  test "leaves capture with only &N references alone" do
    assert analyze("&(&1 + &2)") == []
  end

  test "leaves regular code alone" do
    assert analyze("Map.update(m, 0, fn x -> x + 1 end)") == []
  end
end
