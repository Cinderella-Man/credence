defmodule Credence.Semantic.FixDeprecatedMapMapFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixDeprecatedMapMap

  @message "Map.map/2 is deprecated. Use Map.new/2 instead."

  defp fix(source, message, line \\ 1) do
    FixDeprecatedMapMap.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "fixes the source" do
    input = "Map.map(m, fn {k, v} -> {k, Enum.reverse(v)} end)"

    expected = "Map.new(m, fn {k, v} -> {k, Enum.reverse(v)} end)"

    confirm_fix(fix(input, @message), expected)
  end

  test "fixes the source in a module context" do
    input = """
    defmodule M do
      def transform(map) do
        Map.map(map, fn {k, v} -> {k, Enum.reverse(v)} end)
      end
    end
    """

    expected = """
    defmodule M do
      def transform(map) do
        Map.new(map, fn {k, v} -> {k, Enum.reverse(v)} end)
      end
    end
    """

    confirm_fix(fix(input, @message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = "Map.map(m, fn {k, v} -> {k, v} end)"

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when line has no Map.map(" do
    source = "Enum.map(list, fn x -> x + 1 end)"
    confirm_fix(fix(source, @message), source)
  end

  test "returns source unchanged when position is nil" do
    source = "Map.map(m, fn {k, v} -> {k, v} end)"
    bad_diag = %{severity: :warning, message: @message, position: nil}
    confirm_fix(FixDeprecatedMapMap.fix(source, bad_diag), source)
  end
end
