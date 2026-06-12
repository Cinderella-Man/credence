defmodule Credence.Pattern.PreferMapSizeFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapSize

  test "rewrites Map.keys piped into Enum.count" do
    input = """
    Map.keys(m) |> Enum.count()
    """

    expected = """
    map_size(m)
    """

    assert fix(PreferMapSize, input) == expected
  end

  test "rewrites Enum.count wrapping Map.keys" do
    input = """
    Enum.count(Map.keys(m))
    """

    expected = """
    map_size(m)
    """

    assert fix(PreferMapSize, input) == expected
  end
end
