defmodule Credence.Pattern.NoEnumSortThenMapValuesCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoEnumSortThenMapValues

  describe "flags" do
    test "the nested spelling" do
      assert [%Issue{rule: :no_enum_sort_then_map_values}] =
               check(NoEnumSortThenMapValues, """
               defmodule SortValsCheckA do
                 def f(m), do: Map.values(Enum.sort(m))
               end
               """)
    end

    # The shape docs/17 recorded from the field, with the pipe spelling and
    # `sort_by`. Sourceror does not expand pipes, so this reaches the rule as a
    # `:|>` node whose own left-hand side is another `:|>` node — the sort is
    # the rightmost stage of the left, not the left itself.
    test "the piped spelling, which is how it was actually generated" do
      assert flagged?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckB do
               def f(payments), do: payments |> Enum.sort_by(& &1) |> Map.values()
             end
             """)
    end

    test "a two-stage pipe, where the sort is the immediate left" do
      assert flagged?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckC do
               def f(m), do: Enum.sort(m) |> Map.values()
             end
             """)
    end

    test "mid-pipeline, with stages after the Map.values" do
      assert flagged?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckD do
               def f(m), do: m |> Enum.sort() |> Map.values() |> Enum.take(2)
             end
             """)
    end

    test "Map.values wrapped around a pipe" do
      assert flagged?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckT do
               def f(m), do: Map.values(m |> Enum.sort())
             end
             """)
    end

    test "sort/2 with a direction, and sort_by/3 with a sorter" do
      assert flagged?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckE do
               def f(m), do: Map.values(Enum.sort(m, :desc))
             end
             """)

      assert flagged?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckF do
               def f(m), do: Map.values(Enum.sort_by(m, &elem(&1, 0), :desc))
             end
             """)
    end
  end

  describe "leaves alone" do
    test "a lexical Enum alias" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckAliasedEnum do
               alias MyEnum, as: Enum
               def f(value), do: Map.values(Enum.sort(value))
             end
             """)
    end

    test "Map.values on a map" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckG do
               def f(m), do: Map.values(m)
             end
             """)
    end

    test "the correct order — values first, then sort" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckH do
               def f(m), do: m |> Map.values() |> Enum.sort()
             end
             """)
    end

    # The defect the implementation this rule replaces actually shipped. It
    # searched the whole left subtree for a `sort_by` and flagged anything that
    # merely contained one. Here the argument to `Map.values/1` is a map, so
    # the code is correct — an immediate-neighbour match declines it.
    test "a sort_by buried in the left subtree of a genuine map" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckI do
               def f(s), do: %{sorted: Enum.sort_by(s, & &1)} |> Map.values()
             end
             """)
    end

    # Measured on the corpus: `Enum.group_by/2,3`, `Enum.into/2,3`,
    # `Enum.frequencies/1` and `Enum.reduce/3` with a map seed all return a
    # MAP, and feeding one into `Map.values/1` is ordinary correct Elixir.
    # Eight such sites exist in the corpus and all eight are right.
    test "map-returning Enum functions" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckJ do
               def f(l), do: l |> Enum.group_by(& &1.id) |> Map.values()
             end
             """)

      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckK do
               def f(l), do: l |> Enum.into(%{}) |> Map.values()
             end
             """)

      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckL do
               def f(l), do: l |> Enum.reduce(%{}, &Map.put(&2, &1, &1)) |> Map.values()
             end
             """)
    end

    # `Enum.at/2` and `Enum.find/2` return an ELEMENT, which is a map whenever
    # the enumerable holds maps. 33 corpus sites, all correct.
    test "element-returning Enum functions" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckM do
               def f(l), do: l |> Enum.at(0) |> Map.values()
             end
             """)

      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckN do
               def f(l), do: l |> Enum.find(& &1.ok?) |> Map.values()
             end
             """)
    end

    # `%Stream{}` is a STRUCT, so `Map.values/1` on it returns the struct's
    # four field values rather than raising. docs/17's premise that every
    # `Enum.*`/`Stream.*` returns a list is wrong about Stream, which is why
    # this rule names `Enum.sort*` explicitly instead of a module prefix.
    test "a Stream, which is a struct and not a list" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckO do
               def f(l), do: l |> Stream.map(& &1) |> Map.values()
             end
             """)
    end

    # The argument-position trap: `Map.take/2` and `Map.drop/2` take a LIST as
    # their second argument, so an `Enum.*` call there is required, not a
    # defect. Four corpus sites are exactly this shape.
    test "an Enum call in a Map function's list-typed second argument" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckP do
               def f(m, keys), do: Map.take(m, Enum.sort(keys))
             end
             """)
    end

    # `Map.new/1` is the constructor — it WANTS a list. It is 65% of the
    # corpus sites where an Enum result flows into a Map function.
    test "Map.new, which takes a list by design" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckQ do
               def f(l), do: l |> Enum.sort() |> Map.new()
             end
             """)
    end

    # Deliberately out of scope: the crash is identical, but only
    # `Map.values/1` has field evidence behind it, and `Map.get/2` on a sorted
    # list has no repair anyone can defend.
    test "Map.keys and Map.get on the same result" do
      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckR do
               def f(m), do: m |> Enum.sort() |> Map.keys()
             end
             """)

      assert clean?(NoEnumSortThenMapValues, """
             defmodule SortValsCheckS do
               def f(m), do: Map.get(Enum.sort(m), :a)
             end
             """)
    end
  end
end
