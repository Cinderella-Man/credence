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

  # `_key` is an ordinary variable — the underscore only suppresses the unused warning —
  # so a captured count may legitimately be called that, and `match_merge_stmts/4` admits
  # it (its only name guard is `count1 != count2`). Emitting the literal `:_key` produced
  # `fn _key, _key, count2 -> min(_key, count2) end`, which is a MATCH on one name rather
  # than two parameters: it compiles with warnings and raises FunctionClauseError as soon
  # as Map.intersect/3 passes a key that differs from the value. Executed.
  describe "the key parameter cannot collide with a captured count" do
    test "a count named _key gets a fresh key parameter" do
      source = """
      common_keys =
        Map.keys(freq1)
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
        |> MapSet.to_list()

      common_keys
      |> Enum.map(fn element ->
        _key = Map.fetch!(freq1, element)
        count2 = Map.fetch!(freq2, element)
        {element, min(_key, count2)}
      end)
      |> Enum.sort()
      """

      expected =
        "freq1 |> Map.intersect(freq2, fn _key1, _key, count2 -> min(_key, count2) end) |> Enum.sort()"

      confirm_fix(fix(PreferMapIntersectOverMapsetIntersection, source), expected)
    end

    test "the ordinary case still emits _key" do
      source = """
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

      expected =
        "freq1 |> Map.intersect(freq2, fn _key, count1, count2 -> min(count1, count2) end) |> Enum.sort()"

      confirm_fix(fix(PreferMapIntersectOverMapsetIntersection, source), expected)
    end
  end
end
