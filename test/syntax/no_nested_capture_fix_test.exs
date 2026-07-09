defmodule Credence.Syntax.NoNestedCaptureFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoNestedCapture

  defp analyze(code), do: NoNestedCapture.analyze(code)
  defp fix(code), do: NoNestedCapture.fix(code)

  test "replaces nested capture with fn" do
    input = "&Map.update(&1, 0, &(&1 + 1))"

    expected = "&Map.update(&1, 0, fn x -> x + 1 end)"

    confirm_fix(fix(input), expected)
  end

  test "fixes nested capture in multiline module" do
    input = """
    defmodule WorkStealQueue do
      def run do
        &Map.update(&1, 0, &(&1 + 1))
      end
    end
    """

    expected = """
    defmodule WorkStealQueue do
      def run do
        &Map.update(&1, 0, fn x -> x + 1 end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes nested capture with multiple capture vars" do
    input = "&Enum.reduce(&1, 0, &(&1 + &2))"

    expected = "&Enum.reduce(&1, 0, fn x, y -> x + y end)"

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("&Map.update(&1, 0, &(&1 + 1))")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("&Map.update(&1, 0, &(&1 + 1))"))
  end

  test "leaves code without nested captures unchanged" do
    source = "&Map.update(&1, 0, fn x -> x + 1 end)"

    confirm_fix(fix(source), source)
  end
end
