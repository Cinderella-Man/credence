defmodule Credence.Pattern.PreferMapIntersectOverMapsetIntersectionFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapIntersectOverMapsetIntersection

  test "rewrites the anti-pattern" do
    input = """
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
    """

    expected = """
    freq1
    |> Map.intersect(freq2, fn _key, count1, count2 -> min(count1, count2) end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    """

    assert fix(PreferMapIntersectOverMapsetIntersection, input) == expected
  end
end
