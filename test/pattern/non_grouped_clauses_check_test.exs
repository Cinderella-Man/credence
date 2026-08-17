defmodule Credence.Pattern.NonGroupedClausesCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NonGroupedClauses

  describe "flags non-grouped clauses" do
    test "def separated by another def" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x
        def foo(x), do: x + 1
      end
      """

      assert [%Issue{rule: :non_grouped_clauses}] = check(NonGroupedClauses, code)
    end

    test "defp separated by another defp" do
      code = """
      defmodule M do
        defp helper(1), do: :one
        defp other(x), do: x
        defp helper(x), do: :other
      end
      """

      assert [%Issue{rule: :non_grouped_clauses}] = check(NonGroupedClauses, code)
    end

    test "multiple non-grouped functions" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def bar(1), do: 1
        def foo(x), do: x
        def bar(x), do: x
      end
      """

      assert length(check(NonGroupedClauses, code)) == 2
    end
  end

  # These are the cases the fix deliberately declines, so the check must decline
  # them too — the rule reported all of them and repaired none, which is the
  # report-without-repair shape CONTEXT.md forbids and
  # test/fix_or_drop_test.exs now gates. Both remain worth WIDENING later (the
  # attribute run can travel with its clause; the block body needs a
  # layout-metadata strip), and the fix-side no-op tests pin the current
  # behaviour either way.
  # Both of these used to be declines — the fix could not move a stray preceded by
  # a module attribute (it would orphan the attribute) nor one with a multi-statement
  # block body (it re-rendered as a `do:` one-liner, dropping every statement after
  # the first). Both are repaired now: the annotation run travels with its clause,
  # and the patch covers the whole module rather than diffing statements pairwise.
  describe "flags strays that used to be unmovable" do
    test "a stray preceded by an annotation attribute" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x

        @decorate telemetry([:demo])
        def foo(x), do: x + 1
      end
      """

      assert flagged?(NonGroupedClauses, code)
    end

    test "a stray whose body is a multi-statement block" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x

        def foo(x) do
          y = x + 1
          y * 2
        end
      end
      """

      assert flagged?(NonGroupedClauses, code)
    end
  end

  # The one run that still cannot move. `@threshold 5` is a VALUE definition rather
  # than an annotation: later clauses may read it and its position relative to them
  # is load-bearing, so `attr_run_start/2` answers `:unmovable` and the check
  # declines alongside the fix.
  describe "does not flag a stray behind a non-annotation attribute" do
    test "a value-defining attribute in the run" do
      code = """
      defmodule M do
        @threshold 5
        def foo(1), do: 1
        def bar(x), do: x

        @threshold 9
        def foo(x), do: x + @threshold
      end
      """

      assert clean?(NonGroupedClauses, code)
    end
  end

  describe "does NOT flag grouped clauses" do
    test "consecutive clauses" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def foo(x), do: x + 1
        def bar(x), do: x
      end
      """

      assert check(NonGroupedClauses, code) == []
    end

    test "non-def expressions between clauses" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def foo(x), do: x
      end
      """

      assert check(NonGroupedClauses, code) == []
    end

    test "module attributes between consecutive clauses" do
      code = """
      defmodule M do
        def foo(1), do: 1

        @doc "Handles other values"
        def foo(x), do: x + 1
      end
      """

      assert check(NonGroupedClauses, code) == []
    end

    test "decorator attributes between consecutive clauses" do
      code = """
      defmodule M do
        def foo(1), do: 1

        @decorate telemetry([:demo])
        def foo(x), do: x + 1
      end
      """

      assert check(NonGroupedClauses, code) == []
    end

    test "different arities are different functions" do
      code = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x
        def foo(x, y), do: x + y
      end
      """

      assert check(NonGroupedClauses, code) == []
    end

    test "single clause per function" do
      code = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x * 2
      end
      """

      assert check(NonGroupedClauses, code) == []
    end

    # A directive (require/import/alias) between clauses does not trigger
    # Elixir's grouped-clauses warning, so it must not be flagged.
    test "directive (require) between same clauses is not flagged" do
      code = """
      defmodule M do
        def handle_info(:a, s), do: {:noreply, s}
        require Logger
        def handle_info(:b, s), do: {:noreply, s}
      end
      """

      assert check(NonGroupedClauses, code) == []
    end
  end
end
