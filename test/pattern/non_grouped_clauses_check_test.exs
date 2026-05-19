defmodule Credence.Pattern.NonGroupedClausesCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    Credence.Pattern.NonGroupedClauses.check(ast, [])
  end

  describe "flags non-grouped clauses" do
    test "def separated by another def" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def bar(x), do: x
        def foo(x), do: x + 1
      end
      """

      assert [%Issue{rule: :non_grouped_clauses}] = check(code)
    end

    test "defp separated by another defp" do
      code = """
      defmodule M do
        defp helper(1), do: :one
        defp other(x), do: x
        defp helper(x), do: :other
      end
      """

      assert [%Issue{rule: :non_grouped_clauses}] = check(code)
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

      assert length(check(code)) == 2
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

      assert [%Issue{rule: :non_grouped_clauses}] = check(code)
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

      assert check(code) == []
    end

    test "non-def expressions between clauses" do
      code = """
      defmodule M do
        def foo(1), do: 1
        def foo(x), do: x
      end
      """

      assert check(code) == []
    end

    test "module attributes between consecutive clauses" do
      code = """
      defmodule M do
        def foo(1), do: 1

        @doc "Handles other values"
        def foo(x), do: x + 1
      end
      """

      assert check(code) == []
    end

    test "decorator attributes between consecutive clauses" do
      code = """
      defmodule M do
        def foo(1), do: 1

        @decorate telemetry([:demo])
        def foo(x), do: x + 1
      end
      """

      assert check(code) == []
    end

    test "different arities are different functions" do
      code = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x
        def foo(x, y), do: x + y
      end
      """

      assert check(code) == []
    end

    test "single clause per function" do
      code = """
      defmodule M do
        def foo(x), do: x
        def bar(x), do: x * 2
      end
      """

      assert check(code) == []
    end
  end
end
