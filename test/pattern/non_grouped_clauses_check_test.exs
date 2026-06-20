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

    test "def separated by another def is still flagged when later clause has an attribute" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x

        @decorate telemetry([:demo])
        def foo(x), do: x + 1
      end
      """

      assert [%Issue{rule: :non_grouped_clauses}] = check(NonGroupedClauses, code)
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
