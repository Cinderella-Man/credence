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

    # `Enum.sort()`, not `Enum.sort_by(fn {key, _value} -> key end)`: `1` and
    # `1.0` are distinct map keys that compare EQUAL in term order, so a key-only
    # comparator ties them where the original's `Enum.sort/1` breaks the tie on
    # the value. See the rule moduledoc and the equivalence test's tie inputs.
    expected =
      "freq1 |> Map.intersect(freq2, fn _key, count1, count2 -> min(count1, count2) end) |> Enum.sort()"

    confirm_fix(fix(PreferMapIntersectOverMapsetIntersection, input), expected)
  end
end
