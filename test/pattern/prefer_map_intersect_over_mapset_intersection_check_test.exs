defmodule Credence.Pattern.PreferMapIntersectOverMapsetIntersectionCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapIntersectOverMapsetIntersection

  test "does not flag the intersection assignment alone (nothing to fix safely)" do
    # Without the following `Enum.map |> Enum.sort`, the fix has nothing to
    # rewrite — check and fix must agree, so the bare assignment is not flagged.
    assert clean?(PreferMapIntersectOverMapsetIntersection, """
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

  # ── safety gates ───────────────────────────────────────────────────

  test "does not flag when the merge references the element key" do
    # `{element, count1 * element}` would drop `element` to an unbound `_key`.
    assert clean?(PreferMapIntersectOverMapsetIntersection, """
           common_keys =
             Map.keys(freq1)
             |> MapSet.new()
             |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
             |> MapSet.to_list()

           common_keys
           |> Enum.map(fn element ->
             count1 = Map.fetch!(freq1, element)
             count2 = Map.fetch!(freq2, element)
             {element, count1 * element}
           end)
           |> Enum.sort()
           """)
  end

  test "does not flag an impure merge (side effects make key order observable)" do
    assert clean?(PreferMapIntersectOverMapsetIntersection, """
           common_keys =
             Map.keys(freq1)
             |> MapSet.new()
             |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
             |> MapSet.to_list()

           common_keys
           |> Enum.map(fn element ->
             count1 = Map.fetch!(freq1, element)
             count2 = Map.fetch!(freq2, element)
             {element, IO.inspect(min(count1, count2))}
           end)
           |> Enum.sort()
           """)
  end

  test "does not flag when the intersection variable is reused" do
    # The fix deletes the `common_keys` binding; the trailing use would be unbound.
    assert clean?(PreferMapIntersectOverMapsetIntersection, """
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

           IO.inspect(length(common_keys))
           """)
  end

  # ── D6/C12(c): the measured boundary ───────────────────────────────────
  #
  # This matcher fires on 2 of 8 plausible spellings. The moduledoc records
  # which of its five requirements are load-bearing for equivalence and which
  # are incidental syntax. These tests pin the boundary so that a future
  # widening has to move them deliberately rather than by accident — and so that
  # the three load-bearing ones cannot be widened by someone who reads only the
  # shape.
  describe "the boundary, pinned" do
    defp pipeline(opts) do
      binding? = Keyword.get(opts, :binding?, true)
      sort? = Keyword.get(opts, :sort?, true)
      fetch = Keyword.get(opts, :fetch, "Map.fetch!")
      combiner = Keyword.get(opts, :combiner, "min")

      head =
        if binding? do
          """
              common_keys =
                Map.keys(freq1)
                |> MapSet.new()
                |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
                |> MapSet.to_list()

              common_keys
          """
        else
          """
              Map.keys(freq1)
              |> MapSet.new()
              |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
              |> MapSet.to_list()
          """
        end

      tail = if sort?, do: "\n          |> Enum.sort()", else: ""

      """
      defmodule MiBoundary do
        def f(freq1, freq2) do
      #{String.trim_trailing(head)}
          |> Enum.map(fn element ->
            count1 = #{fetch}(freq1, element)
            count2 = #{fetch}(freq2, element)
            {element, #{combiner}(count1, count2)}
          end)#{tail}
        end
      end
      """
    end

    test "the documented shape fires" do
      assert flagged?(PreferMapIntersectOverMapsetIntersection, pipeline([]))
    end

    # The combiner is already general — it is carried into the repair rather
    # than assumed, so both directions are matched.
    test "max fires as well as min" do
      assert flagged?(PreferMapIntersectOverMapsetIntersection, pipeline(combiner: "max"))
    end

    # ── Load-bearing: widening any of these would change behaviour ──

    test "LOAD-BEARING: without the trailing Enum.sort it does not fire" do
      refute flagged?(PreferMapIntersectOverMapsetIntersection, pipeline(sort?: false)),
             "Map.intersect/3 returns a map; without the trailing sort the " <>
               "rewrite would silently reorder the result"
    end

    test "LOAD-BEARING: Map.get instead of Map.fetch! does not fire" do
      refute flagged?(PreferMapIntersectOverMapsetIntersection, pipeline(fetch: "Map.get")),
             "Map.fetch! raises on a missing key and Map.get returns nil; the " <>
               "two are only interchangeable while the keys come from the intersection"
    end

    # ── Incidental: this is the gain a widening would buy, and it is not taken ──

    test "INCIDENTAL: an inlined pipeline with no binding does not fire, and could" do
      refute flagged?(PreferMapIntersectOverMapsetIntersection, pipeline(binding?: false))
    end
  end

  # Two defects that shipped, both found by reading the matcher against its emission and
  # then EXECUTED. Neither was catchable by the accept/revert gate, which reverts only on
  # non-compiling output — both of these compile.
  describe "soundness gates" do
    # The operands are matched by name only and the consumer may sit at any later index,
    # so a statement in between could rebind `freq1` and be passed through verbatim while
    # the emitted Map.intersect/3 read the NEW value. Measured before the gate:
    #   ADD a key: original [b: 2]          -> repair [b: 2, x: 7]
    #   DEL a key: original raises KeyError -> repair []
    test "declines when a statement between the two halves rebinds an operand" do
      source = """
      freq1 = %{a: 1, b: 2}
      freq2 = %{b: 5, x: 7}

      common_keys =
        Map.keys(freq1)
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
        |> MapSet.to_list()

      freq1 = Map.put(freq1, :x, 9)

      common_keys
      |> Enum.map(fn element ->
        count1 = Map.fetch!(freq1, element)
        count2 = Map.fetch!(freq2, element)
        {element, min(count1, count2)}
      end)
      |> Enum.sort()
      """

      refute flagged?(PreferMapIntersectOverMapsetIntersection, source)
    end

    test "declines when a rebinding expression ends in an unrelated variable" do
      source = """
      common_keys =
        Map.keys(freq1)
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
        |> MapSet.to_list()

      freq1 = replacement

      common_keys
      |> Enum.map(fn element ->
        count1 = Map.fetch!(freq1, element)
        count2 = Map.fetch!(freq2, element)
        {element, min(count1, count2)}
      end)
      |> Enum.sort()
      """

      refute flagged?(PreferMapIntersectOverMapsetIntersection, source)
    end

    test "declines when the rebinding is of the second operand" do
      source = """
      common_keys =
        Map.keys(freq1)
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
        |> MapSet.to_list()

      freq2 = Map.delete(freq2, :b)

      common_keys
      |> Enum.map(fn element ->
        count1 = Map.fetch!(freq1, element)
        count2 = Map.fetch!(freq2, element)
        {element, min(count1, count2)}
      end)
      |> Enum.sort()
      """

      refute flagged?(PreferMapIntersectOverMapsetIntersection, source)
    end

    # An intervening statement that does not touch either operand is still fine — the gate
    # must not turn the rule off wholesale.
    test "still fires with an unrelated statement between the two halves" do
      source = """
      common_keys =
        Map.keys(freq1)
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
        |> MapSet.to_list()

      total = 0

      common_keys
      |> Enum.map(fn element ->
        count1 = Map.fetch!(freq1, element)
        count2 = Map.fetch!(freq2, element)
        {element, min(count1, count2)}
      end)
      |> Enum.sort()
      """

      assert flagged?(PreferMapIntersectOverMapsetIntersection, source)
    end
  end
end
