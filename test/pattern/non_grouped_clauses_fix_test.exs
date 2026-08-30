defmodule Credence.Pattern.NonGroupedClausesFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NonGroupedClauses
  alias Credence.RuleHelpers

  describe "reorders stray clauses to join siblings" do
    test "repairs scattered clauses in nested and enclosing modules without overlapping patches" do
      input = """
      defmodule OuterNestedGrouping do
        def foo(1), do: 1
        defmodule InnerNestedGrouping do
          def baz(1), do: 1
          def qux(x), do: x
          def baz(x), do: x
        end
        def bar(x), do: x
        def foo(x), do: x
      end
      """

      expected = """
      defmodule OuterNestedGrouping do
        def foo(1), do: 1
        def foo(x), do: x
        defmodule InnerNestedGrouping do
          def baz(1), do: 1
          def baz(x), do: x
          def qux(x), do: x
        end
        def bar(x), do: x
      end
      """

      emitted = fix(NonGroupedClauses, input)
      confirm_fix(emitted, expected)
      assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
      confirm_fix(fix(NonGroupedClauses, emitted), emitted)
    end

    test "simple case: def foo, def bar, def foo → grouped" do
      input = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x
        def foo(x), do: x + 1
      end
      """

      expected = """
      defmodule M do
        def foo(1), do: 1
        def foo(x), do: x + 1
        def bar(x), do: x
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    test "three clauses of same function" do
      input = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x
        def foo(2), do: 2
        def baz(x), do: x
        def foo(x), do: x + 1
      end
      """

      expected = """
      defmodule M do
        def foo(1), do: 1
        def foo(2), do: 2
        def foo(x), do: x + 1
        def bar(x), do: x
        def baz(x), do: x
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    test "defp clauses grouped" do
      input = """
      defmodule M do
        defp helper(1), do: :one
        defp other(x), do: x
        defp helper(x), do: :other
      end
      """

      expected = """
      defmodule M do
        defp helper(1), do: :one
        defp helper(x), do: :other
        defp other(x), do: x
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end
  end

  describe "preserves content" do
    test "module attributes stay in place" do
      input = """
      defmodule M do
        @moduledoc false
        def foo(1), do: 1
        def bar(x), do: x
        def foo(x), do: x + 1
      end
      """

      expected = """
      defmodule M do
        @moduledoc false
        def foo(1), do: 1
        def foo(x), do: x + 1
        def bar(x), do: x
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    test "different arities not mixed" do
      input = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x
        def foo(x, y), do: x + y
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), input)
    end

    test "module attributes between consecutive clauses stay in place" do
      input = """
      defmodule M do
        def foo(1), do: 1

        @decorate telemetry([:demo])
        def foo(x), do: x + 1
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), input)
    end
  end

  describe "no-ops" do
    test "already grouped — no change" do
      input = """
      defmodule M do
        def foo(1), do: 1
        def foo(x), do: x + 1
        def bar(x), do: x
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), input)
    end

    test "single clause per function — no change" do
      input = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x * 2
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), input)
    end

    # These five used to assert no-ops. All are repaired now — the annotation run
    # moves with its clause, and the fix emits ONE patch covering the whole module
    # instead of relying on a positional statement-by-statement diff, which is what
    # spliced two clauses onto one line the first time this was attempted.
    test "moves a stray clause together with its @impl true" do
      input = """
      defmodule M do
        @impl true
        def handle_event("a", _, s), do: s

        def helper(x), do: x

        @impl true
        def handle_event("b", _, s), do: s
      end
      """

      expected = """
      defmodule M do
        @impl true
        def handle_event("a", _, s), do: s

        @impl true
        def handle_event("b", _, s), do: s
        def helper(x), do: x
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    test "moves a stray clause together with its @decorate" do
      input = """
      defmodule M do
        def foo(1), do: 1

        def bar(x), do: x

        @decorate telemetry([:demo])
        def foo(x), do: x + 1
      end
      """

      expected = """
      defmodule M do
        def foo(1), do: 1

        @decorate telemetry([:demo])
        def foo(x), do: x + 1
        def bar(x), do: x
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    # Regression (row 96344), now inverted. This stray USED to be reordered into a
    # broken `def …, do: stmt1` one-liner that dropped stmt2, so it was declined.
    # The whole-module patch renders the block from its own metadata, so both
    # statements survive.
    test "moves a stray clause with a multi-statement block body" do
      input = """
      defmodule M do
        def foo(_x), do: -1

        def bar(y), do: y

        def foo([_ | _] = z) do
          t = Enum.sum(z)
          t + 1
        end
      end
      """

      expected = """
      defmodule M do
        def foo(_x), do: -1

        def foo([_ | _] = z) do
          t = Enum.sum(z)
          t + 1
        end
        def bar(y), do: y
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    test "groups several functions' strays in one pass" do
      input = """
      defmodule M do
        def foo(0), do: :zero

        def bar(y), do: y

        def foo([_ | _] = z) do
          t = Enum.sum(z)
          t + 1
        end

        def baz(1), do: :one

        def qux(w), do: w

        def baz(n), do: n
      end
      """

      expected = """
      defmodule M do
        def foo(0), do: :zero

        def foo([_ | _] = z) do
          t = Enum.sum(z)
          t + 1
        end

        def bar(y), do: y

        def baz(1), do: :one

        def baz(n), do: n
        def qux(w), do: w
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    # A body that is itself a `do…end` construct. Declining this was the third
    # decline reason; the block is now re-rendered from its own metadata intact.
    test "moves a stray clause whose body is a single do-block construct" do
      input = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x

        def foo(x) do
          case x do
            _ -> x
          end
        end
      end
      """

      expected = """
      defmodule M do
        def foo(1), do: 1
        def foo(x) do
          case x do
            _ -> x
          end
        end
        def bar(x), do: x
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    # Still declined: `@threshold` is a value definition, not an annotation, so the
    # run is `:unmovable` and `check/2` declines with it.
    test "leaves a stray behind a non-annotation attribute alone" do
      input = """
      defmodule M do
        @threshold 5
        def foo(1), do: 1
        def bar(x), do: x

        @threshold 9
        def foo(x), do: x + @threshold
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), input)
    end
  end
end
