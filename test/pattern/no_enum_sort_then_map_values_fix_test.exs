defmodule Credence.Pattern.NoEnumSortThenMapValuesFixTest do
  @moduledoc """
  Fixtures are bound as `input = "..."` deliberately.

  Four gates — `dsl_safety_classification_test`, `dsl_macro_protection_test`,
  `comment_preservation_test` and `pattern/attribute_preservation_test` — read
  their fixtures out of this file by looking for that binding, and see nothing
  at all for a rule that inlines its snippets into the assertion. Both of the
  two rules that landed before this one inline theirs and get no coverage from
  any of the four.
  """
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEnumSortThenMapValues

  describe "rewrites" do
    test "the nested spelling" do
      input = """
      defmodule SortValsFixA do
        def f(m), do: Map.values(Enum.sort(m))
      end
      """

      expected = """
      defmodule SortValsFixA do
        def f(m), do: Enum.map(Enum.sort(m), fn {_key, value} -> value end)
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), expected)
    end

    test "the piped spelling, keeping the pipeline a pipeline" do
      input = """
      defmodule SortValsFixB do
        def f(payments), do: payments |> Enum.sort_by(& &1.date) |> Map.values()
      end
      """

      expected = """
      defmodule SortValsFixB do
        def f(payments), do: payments |> Enum.sort_by(& &1.date) |> Enum.map(fn {_key, value} -> value end)
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), expected)
    end

    test "a two-stage pipe, where the sort is the immediate left" do
      input = """
      defmodule SortValsFixC do
        def f(m), do: Enum.sort(m) |> Map.values()
      end
      """

      expected = """
      defmodule SortValsFixC do
        def f(m), do: Enum.sort(m) |> Enum.map(fn {_key, value} -> value end)
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), expected)
    end

    # The stages after `Map.values/1` must survive untouched — the patch
    # replaces one stage of the pipeline, not the pipeline.
    test "mid-pipeline, leaving the later stages alone" do
      input = """
      defmodule SortValsFixD do
        def f(m), do: m |> Enum.sort() |> Map.values() |> Enum.take(2)
      end
      """

      expected = """
      defmodule SortValsFixD do
        def f(m), do: m |> Enum.sort() |> Enum.map(fn {_key, value} -> value end) |> Enum.take(2)
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), expected)
    end

    # The fourth spelling: nested over a pipe. Missed by the first draft, which
    # tested the nested argument for a sort call directly instead of taking the
    # rightmost stage of it the way the pipe clause already did.
    test "Map.values wrapped around a pipe" do
      input = """
      defmodule SortValsFixL do
        def f(m), do: Map.values(m |> Enum.sort())
      end
      """

      expected = """
      defmodule SortValsFixL do
        def f(m), do: Enum.map(m |> Enum.sort(), fn {_key, value} -> value end)
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), expected)
    end

    # The sorter argument is carried through verbatim. This is the whole reason
    # the repair replaces `Map.values/1` rather than hoisting it in front of the
    # sort: `&elem(&1, 1).total` is written to receive a `{key, value}` tuple,
    # and moving `Map.values/1` ahead of it would hand it a bare value instead.
    test "a sorter that reads the tuple keeps receiving a tuple" do
      input = """
      defmodule SortValsFixE do
        def f(m), do: m |> Enum.sort_by(&elem(&1, 1).total, :desc) |> Map.values()
      end
      """

      expected = """
      defmodule SortValsFixE do
        def f(m), do: m |> Enum.sort_by(&elem(&1, 1).total, :desc) |> Enum.map(fn {_key, value} -> value end)
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), expected)
    end
  end

  describe "declines, byte for byte" do
    test "a map-returning Enum function" do
      input = """
      defmodule SortValsFixF do
        def f(l), do: l |> Enum.group_by(& &1.id) |> Map.values()
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), input)
    end

    test "an Enum call in Map.take's list-typed second argument" do
      input = """
      defmodule SortValsFixG do
        def f(m, keys), do: Map.take(m, Enum.sort(keys))
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), input)
    end

    test "Map.new, which takes a list by design" do
      input = """
      defmodule SortValsFixH do
        def f(l), do: l |> Enum.sort() |> Map.new()
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), input)
    end

    test "a sort_by buried in the left subtree of a genuine map" do
      input = """
      defmodule SortValsFixI do
        def f(s), do: %{sorted: Enum.sort_by(s, & &1)} |> Map.values()
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), input)
    end
  end

  describe "the output" do
    test "parses, and is a fixpoint after one pass" do
      input = """
      defmodule SortValsFixJ do
        def f(m), do: Map.values(Enum.sort(m))
      end
      """

      fixed = fix(NoEnumSortThenMapValues, input)

      assert valid_syntax?(fixed)
      assert compiles?(fixed)
      confirm_fix(fix(NoEnumSortThenMapValues, fixed), fixed)
    end

    test "two offending sites in one module both get repaired" do
      input = """
      defmodule SortValsFixK do
        def a(m), do: Map.values(Enum.sort(m))
        def b(m), do: m |> Enum.sort_by(& &1) |> Map.values()
      end
      """

      expected = """
      defmodule SortValsFixK do
        def a(m), do: Enum.map(Enum.sort(m), fn {_key, value} -> value end)
        def b(m), do: m |> Enum.sort_by(& &1) |> Enum.map(fn {_key, value} -> value end)
      end
      """

      confirm_fix(fix(NoEnumSortThenMapValues, input), expected)
    end
  end
end
