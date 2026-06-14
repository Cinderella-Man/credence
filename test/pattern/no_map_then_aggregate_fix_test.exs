defmodule Credence.Pattern.NoMapThenAggregateFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMapThenAggregate

  describe "NoMapThenAggregate fix" do
    test "does not flag Enum.map |> Enum.max (selection — unmapped seed, not fusable)" do
      code = "list |> Enum.map(&String.length/1) |> Enum.max()"

      confirm_fix(fix(NoMapThenAggregate, code), code)
    end

    test "does not flag Enum.map |> Enum.min (selection — unmapped seed, not fusable)" do
      code = "list |> Enum.map(&String.length/1) |> Enum.min()"

      confirm_fix(fix(NoMapThenAggregate, code), code)
    end

    test "fixes basic pipeline: Enum.map |> Enum.sum" do
      input = "list |> Enum.map(&byte_size/1) |> Enum.sum()"

      expected = "list |> Enum.reduce(0, fn el, acc -> acc + byte_size(el) end)"

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "fixes three-step pipeline with preceding step" do
      input = """
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.map(&Enum.sum/1)
      |> Enum.sum()
      """

      expected = """
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.reduce(0, fn el, acc ->
        acc + Enum.sum(el)
      end)
      """

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "fixes two-step pipeline (explicit source)" do
      input = "Enum.map(list, &String.length/1) |> Enum.sum()"

      expected = "Enum.reduce(list, 0, fn el, acc -> acc + String.length(el) end)"

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "does not flag direct nesting Enum.max(Enum.map(...)) (selection — not fusable)" do
      code = "Enum.max(Enum.map(list, &String.length/1))"

      confirm_fix(fix(NoMapThenAggregate, code), code)
    end

    test "fixes direct nesting: Enum.sum(Enum.map(enum, f))" do
      input = "Enum.sum(Enum.map(list, fn x -> x * x end))"

      expected = "Enum.reduce(list, 0, fn el, acc -> acc + el * el end)"

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "fixes pipeline with anonymous function" do
      input = """
      readings
      |> Enum.map(fn {_, temp} -> temp end)
      |> Enum.sum()
      """

      expected = """
      readings
      |> Enum.reduce(0, fn el, acc ->
        acc + (fn {_, temp} -> temp end).(el)
      end)
      """

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "fixes pipeline with capture syntax" do
      input = "strings |> Enum.map(&byte_size/1) |> Enum.sum()"

      expected = "strings |> Enum.reduce(0, fn el, acc -> acc + byte_size(el) end)"

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "fix does not modify code without map-aggregate pattern" do
      code = "list |> Enum.map(&(&1 * 2)) |> Enum.filter(&(&1 > 0))"

      confirm_fix(fix(NoMapThenAggregate, code), code)
    end
  end

  describe "NoMapThenAggregate fix — locality (issue: collapses multi-line pipes)" do
    test "preserves surrounding code byte-identically outside the change site" do
      input = """
      defmodule Test do
        def compute(items, dim) do
          weighted =
            items
            |> Enum.map(fn item ->
              Enum.at(item.weights, dim, 0)
            end)
            |> Enum.sum()

          {:ok, weighted}
        end
      end
      """

      expected = """
      defmodule Test do
        def compute(items, dim) do
          weighted =
            items
            |> Enum.reduce(0, fn el, acc ->
              acc + Enum.at(el.weights, dim, 0)
            end)

          {:ok, weighted}
        end
      end
      """

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "keeps the replacement multi-line when the original pipeline was multi-line" do
      input = """
      defmodule Test do
        def compute(items, dim) do
          items
          |> Enum.map(fn item -> Enum.at(item.weights, dim, 0) end)
          |> Enum.sum()
        end
      end
      """

      expected = """
      defmodule Test do
        def compute(items, dim) do
          items
          |> Enum.reduce(0, fn el, acc ->
            acc + Enum.at(el.weights, dim, 0)
          end)
        end
      end
      """

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end
  end

  describe "NoMapThenAggregate fix — closure-parameter substitution (issue: c.delivery survives)" do
    test "substitutes closure parameter through a dot-access in the body" do
      input = "clients |> Enum.map(fn c -> Enum.at(c.delivery, dim, 0) end) |> Enum.sum()"

      expected = "clients |> Enum.reduce(0, fn el, acc -> acc + Enum.at(el.delivery, dim, 0) end)"

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "substitutes closure parameter through a chained dot-access (r.inner.field)" do
      input = "records |> Enum.map(fn r -> r.inner.field end) |> Enum.sum()"

      expected = "records |> Enum.reduce(0, fn el, acc -> acc + el.inner.field end)"

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "substitutes closure parameter inside a remote-call argument" do
      input = "strings |> Enum.map(fn s -> String.length(s) end) |> Enum.sum()"

      expected = "strings |> Enum.reduce(0, fn el, acc -> acc + String.length(el) end)"

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end

    test "full module repro from the GitHub issue compiles" do
      input = """
      defmodule Test do
        def calc(clients, dim) do
          clients
          |> Enum.map(fn c -> Enum.at(c.delivery, dim, 0) end)
          |> Enum.sum()
        end
      end
      """

      expected = """
      defmodule Test do
        def calc(clients, dim) do
          clients
          |> Enum.reduce(0, fn el, acc ->
            acc + Enum.at(el.delivery, dim, 0)
          end)
        end
      end
      """

      confirm_fix(fix(NoMapThenAggregate, input), expected)
    end
  end
end
