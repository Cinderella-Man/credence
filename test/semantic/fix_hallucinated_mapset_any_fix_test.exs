defmodule Credence.Semantic.FixHallucinatedMapsetAnyFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedMapsetAny

  @message "MapSet.any?/2 is undefined or private"

  defp fix(source, message, line \\ 1) do
    FixHallucinatedMapsetAny.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces MapSet.any? with Enum.any?" do
    input = """
    defmodule MapSetAnyFix do
      def has_active?(mapset, tombstones) do
        MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    expected = """
    defmodule MapSetAnyFix do
      def has_active?(mapset, tombstones) do
        Enum.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MapSetAnyFix do
      def has_active?(mapset, tombstones) do
        MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no MapSet.any? present" do
    input = """
    defmodule CleanExample do
      def check(set), do: MapSet.member?(set, :foo)
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
