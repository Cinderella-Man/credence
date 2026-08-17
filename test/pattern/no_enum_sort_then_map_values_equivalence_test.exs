defmodule Credence.Pattern.NoEnumSortThenMapValuesEquivalenceTest do
  @moduledoc """
  `assert_equivalent/2` cannot apply: it compares a before-expression against an
  after-expression over a set of inputs, and the before raises on every input
  there is. That is exactly what makes this a repair rather than a behaviour
  change, so the rule is marked and both halves of the claim are EXECUTED.

  There is a second thing to prove here that the ETS repairs did not have to.
  Those had one possible repair. This one had two, they are different programs,
  and the tests below run both.
  """
  use Credence.RuleCase, async: false

  alias Credence.Pattern.NoEnumSortThenMapValues

  test "marked as a repair: the before raises for every input" do
    mark_equivalence_repair(
      "always-fails. `Enum.sort/1,2` and `Enum.sort_by/2,3` are spec'd `:: list`, so " <>
        "`Map.values/1` on the result calls `:maps.values/1` on a list and raises " <>
        "BadMapError — for every map, every key, every value and every caller, the " <>
        "empty map included. There is no input on which the before-code returns a " <>
        "value the rewrite could disagree with. Executed below."
    )

    assert_raise BadMapError, fn -> Map.values(Enum.sort(%{a: 3, b: 1})) end
    assert_raise BadMapError, fn -> Map.values(Enum.sort(%{})) end
    assert_raise BadMapError, fn -> Map.values(Enum.sort_by(%{a: 1}, &elem(&1, 0))) end
  end

  test "the rewritten module returns values where the original raised" do
    before_src = """
    defmodule SortValsEquivRule do
      def f(m), do: Map.values(Enum.sort(m))
    end
    """

    fixed = fix(NoEnumSortThenMapValues, before_src)
    assert fixed != before_src

    assert_raise BadMapError, fn ->
      call_fixed(before_src, SortValsEquivRule, :f, [%{a: 3, b: 1, c: 2}])
    end

    assert call_fixed(fixed, SortValsEquivRule, :f, [%{a: 3, b: 1, c: 2}]) == [3, 1, 2]
  end

  # The two readings of the broken source are different programs on the same
  # input, so "the before always raises" does not by itself settle which repair
  # to emit. This runs both and pins the difference.
  test "the repair this rule does NOT emit gives a different answer" do
    m = %{a: 3, b: 1, c: 2}

    values_in_key_order = m |> Enum.sort() |> Enum.map(fn {_key, value} -> value end)
    values_sorted_by_value = m |> Map.values() |> Enum.sort()

    assert values_in_key_order == [3, 1, 2]
    assert values_sorted_by_value == [1, 2, 3]
    refute values_in_key_order == values_sorted_by_value

    emitted = """
    defmodule SortValsEquivChoice do
      def f(m), do: Map.values(Enum.sort(m))
    end
    """

    assert call_fixed(fix(NoEnumSortThenMapValues, emitted), SortValsEquivChoice, :f, [m]) ==
             values_in_key_order
  end

  # And the deciding argument for that choice: hoisting `Map.values/1` in front
  # of the sort changes what the author's own sorter receives. Here it reads
  # `elem(pair, 1)`, which is meaningful for a `{key, value}` tuple and raises
  # for a bare value — so the alternative repair would take an
  # always-BadMapError program and hand back an always-ArgumentError one.
  test "hoisting Map.values ahead of the sort breaks the author's sorter" do
    m = %{a: %{total: 3}, b: %{total: 1}}

    kept_as_written = m |> Enum.sort_by(&elem(&1, 1).total) |> Enum.map(fn {_k, v} -> v end)
    assert kept_as_written == [%{total: 1}, %{total: 3}]

    assert_raise ArgumentError, fn -> m |> Map.values() |> Enum.sort_by(&elem(&1, 1).total) end
  end

  test "the emitted mapper is the identity on the pairs a sorted map yields" do
    m = %{a: 1, b: 2, c: 3}

    sorted_pairs = Enum.sort(m)
    assert sorted_pairs == [a: 1, b: 2, c: 3]

    assert Enum.map(sorted_pairs, fn {_key, value} -> value end) == [1, 2, 3]
    assert Enum.map(sorted_pairs, fn {key, _value} -> key end) == [:a, :b, :c]
  end
end
