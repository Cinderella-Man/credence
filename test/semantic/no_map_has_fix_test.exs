defmodule Credence.Semantic.NoMapHasFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoMapHas

  @matching_msg "Map.has?/2 is undefined or private"

  defp fix(source, line) do
    NoMapHas.fix(source, %{severity: :warning, message: @matching_msg, position: {line, 1}})
  end

  test "fixes Map.has? to Map.has_key?" do
    input = """
    defmodule Example do
      def has_key?(map, key) do
        Map.has?(map, key)
      end
    end
    """

    expected = """
    defmodule Example do
      def has_key?(map, key) do
        Map.has_key?(map, key)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "rewrites only the stdlib Map.has? when another *Map.has? shares the line" do
    input = """
    defmodule Example do
      def check(m, k) do
        SomeMap.has?(m, k) or Map.has?(m, k)
      end
    end
    """

    expected = """
    defmodule Example do
      def check(m, k) do
        SomeMap.has?(m, k) or Map.has_key?(m, k)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def has_key?(map, key) do
        Map.has?(map, key)
      end
    end
    """

    assert valid_syntax?(fix(input, 3))
  end
end
