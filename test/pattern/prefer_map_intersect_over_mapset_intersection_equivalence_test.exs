defmodule Credence.Pattern.PreferMapIntersectOverMapsetIntersectionEquivalenceTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapIntersectOverMapsetIntersection

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      freq1 = Enum.frequencies(lst1)
      freq2 = Enum.frequencies(lst2)

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
      """,
      rule: PreferMapIntersectOverMapsetIntersection,
      vars: [:lst1, :lst2],
      inputs: [
        {[1, 2, 3], [2, 3, 4]},
        {[1, 1, 2], [1, 2, 2]},
        {[1, 2], [3, 4]},
        {[1, 1, 1], [1, 1]},
        # >32 distinct keys: MapSet.to_list and Map.intersect enumerate in
        # different orders, but the pure merge + final sort make them identical.
        {Enum.to_list(1..50), Enum.to_list(25..75)}
      ]
    )
  end
end
