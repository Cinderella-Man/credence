defmodule Credence.Pattern.PreferMapSizeCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapSize

  test "flags Map.keys piped into Enum.count" do
    assert flagged?(PreferMapSize, "Map.keys(m) |> Enum.count()")
  end

  test "flags Enum.count wrapping Map.keys" do
    assert flagged?(PreferMapSize, "Enum.count(Map.keys(m))")
  end

  test "leaves map_size alone" do
    assert clean?(PreferMapSize, "map_size(m)")
  end

  test "leaves Map.keys alone" do
    assert clean?(PreferMapSize, "Map.keys(m)")
  end

  test "leaves Enum.count alone" do
    assert clean?(PreferMapSize, "Enum.count(m)")
  end

  test "leaves Enum.count with predicate alone" do
    assert clean?(PreferMapSize, "Enum.count(m, &(&1 > 0))")
  end
end
