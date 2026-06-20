defmodule Credence.Pattern.NonGroupedClausesFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NonGroupedClauses

  describe "reorders stray clauses to join siblings" do
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

    test "does not move a stray clause preceded by @impl true" do
      input = """
      defmodule M do
        @impl true
        def handle_event("a", _, s), do: s

        def helper(x), do: x

        @impl true
        def handle_event("b", _, s), do: s
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), input)
    end

    test "does not move a stray clause preceded by @decorate" do
      input = """
      defmodule M do
        def foo(1), do: 1

        def bar(x), do: x

        @decorate telemetry([:demo])
        def foo(x), do: x + 1
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), input)
    end

    # Regression (row 96344): a stray clause with a MULTI-STATEMENT block body
    # used to be reordered into a broken `def ..., do: stmt1` one-liner (dropping
    # stmt2) → non-compiling → the whole fix reverted. It is now left in place.
    test "does not move a stray clause with a multi-statement block body" do
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

      confirm_fix(fix(NonGroupedClauses, input), input)
    end

    # ...but other safe strays still regroup even when a block-body stray is present.
    test "groups do: strays while leaving the block-body stray alone" do
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

        def bar(y), do: y

        def foo([_ | _] = z) do
          t = Enum.sum(z)
          t + 1
        end

        def baz(1), do: :one

        def baz(n), do: n

        def qux(w), do: w
      end
      """

      confirm_fix(fix(NonGroupedClauses, input), expected)
    end

    # A stray clause whose single-statement body is a `do…end` block (here a
    # `case`) must not be moved — re-rendering it would collapse the block to a
    # `do:` one-liner and re-bind the trailing block to `def` (uncompilable). It
    # is left in place (check still flags it).
    test "does not move a stray clause whose body is a single do-block construct" do
      code = """
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

      confirm_fix(fix(NonGroupedClauses, code), code)
    end
  end
end
