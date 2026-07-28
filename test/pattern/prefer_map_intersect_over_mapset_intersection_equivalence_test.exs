defmodule Credence.Pattern.PreferMapIntersectOverMapsetIntersectionEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), **value-kind dimension** (C2.2).

  The whole risk of this rewrite is what the final sort does to two entries whose
  keys are `==` but not `===`. Map keys are unique under `===`, but `Enum.sort/1`
  orders by Erlang *term* order, where `1` and `1.0` compare **equal** — so the
  keys of a map holding both tie under any key-only comparator. The rule used to
  emit `Enum.sort_by(fn {key, _value} -> key end)` on the (false) argument that
  "keys are unique, so sorting by key equals sorting by the whole tuple", and on
  `{[1, 1, 1, 1.0], [1, 1, 1, 1.0, 1.0]}` the original returned
  `[{1.0, 1}, {1, 3}]` while the rewrite returned `[{1, 3}, {1.0, 1}]`. The fix
  now re-emits the original's own `Enum.sort/1`; the tie inputs below are what
  makes that visible, and they were missing when the bug shipped.
  """
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
        {Enum.to_list(1..50), Enum.to_list(25..75)},
        # value-kind ties: `1` and `1.0` are DISTINCT map keys that compare EQUAL
        # in term order, so both survive the intersection and then tie in the
        # sort. The first pair is the one the `sort_by(key)` emission got wrong —
        # the counts differ (3 vs 1), so `Enum.sort/1` breaks the tie on the value
        # while a key-only comparator leaves it to map order.
        {[1, 1, 1, 1.0], [1, 1, 1, 1.0, 1.0]},
        {[1.0, 1.0, 1.0, 1], [1.0, 1.0, 1.0, 1, 1]},
        {[1, 1.0, 2], [1, 1.0, 2]},
        {[0, 0.0, 0.0, 5], [0, 0, 0.0, 5]},
        # a tie pair AND >32 keys: hash-order enumeration plus the tie
        {Enum.to_list(1..50) ++ [1.0, 1.0], Enum.to_list(25..75) ++ [1.0]}
      ]
    )
  end
end
