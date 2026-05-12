defmodule Credence.Pattern.NonGroupedClausesFixTest do
  use ExUnit.Case

  defp fix(code) do
    result = Credence.Pattern.NonGroupedClauses.fix(code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

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

      assert fix(input) == expected
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

      assert fix(input) == expected
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

      assert fix(input) == expected
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

      assert fix(input) == expected
    end

    test "different arities not mixed" do
      input = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x
        def foo(x, y), do: x + y
      end
      """

      assert fix(input) == input
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

      assert fix(input) == input
    end

    test "single clause per function — no change" do
      input = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x * 2
      end
      """

      assert fix(input) == input
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

      assert fix(input) == input
    end
  end
end
