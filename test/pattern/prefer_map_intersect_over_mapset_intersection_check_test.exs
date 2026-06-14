defmodule Credence.Pattern.PreferMapIntersectOverMapsetIntersectionCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapIntersectOverMapsetIntersection

  test "flags the MapSet intersection pipeline" do
    assert flagged?(PreferMapIntersectOverMapsetIntersection, """
           common_keys =
             Map.keys(freq1)
             |> MapSet.new()
             |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
             |> MapSet.to_list()
           """)
  end

  test "flags the pipeline in a full function context" do
    assert flagged?(PreferMapIntersectOverMapsetIntersection, """
           common_keys =
             Map.keys(freq1)
             |> MapSet.new()
             |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
             |> MapSet.to_list()

           common_keys
           |> Enum.map(fn element ->
             count1 = Map.fetch!(freq1, element)
             count2 = Map.fetch!(freq2, element)
             {element, min(count1, count2)}
           end)
           |> Enum.sort()
           """)
  end

  test "leaves Map.intersect code alone" do
    assert clean?(PreferMapIntersectOverMapsetIntersection, """
           freq1
           |> Map.intersect(freq2, fn _key, count1, count2 -> min(count1, count2) end)
           |> Enum.sort_by(fn {key, _value} -> key end)
           """)
  end

  test "leaves plain MapSet operations alone" do
    assert clean?(PreferMapIntersectOverMapsetIntersection, "MapSet.new([1, 2, 3])")
  end

  test "leaves MapSet intersection without Map.keys alone" do
    assert clean?(
             PreferMapIntersectOverMapsetIntersection,
             "MapSet.new(a) |> MapSet.intersection(MapSet.new(b)) |> MapSet.to_list()"
           )
  end
end
