defmodule Credence.Pattern.NoRedundantUnderscoreBindFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantUnderscoreBind

  describe "rewrites the anti-pattern" do
    test "in function head" do
      input = """
      defmodule Example do
        def foo(_ = x), do: x + 1
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == expected
    end

    test "in multi-arg function" do
      input = """
      defmodule Example do
        def foo(a, _ = b, c), do: a + b + c
      end
      """

      expected = """
      defmodule Example do
        def foo(a, b, c), do: a + b + c
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == expected
    end

    test "in private function" do
      input = """
      defmodule Example do
        defp bar(_ = x), do: x * 2
      end
      """

      expected = """
      defmodule Example do
        defp bar(x), do: x * 2
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == expected
    end

    test "multiple occurrences" do
      input = """
      defmodule Example do
        def foo(_ = a, _ = b), do: a + b
      end
      """

      expected = """
      defmodule Example do
        def foo(a, b), do: a + b
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == expected
    end

    test "in case clause" do
      input = """
      case val do
        _ = x -> x + 1
      end
      """

      expected = """
      case val do
        x -> x + 1
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == expected
    end
  end

  describe "does not modify already-idiomatic code" do
    test "simple variable" do
      input = """
      defmodule Example do
        def foo(x), do: x + 1
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == input
    end

    test "literal pattern" do
      input = """
      defmodule Example do
        def foo(1), do: :one
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == input
    end

    test "tuple pattern" do
      input = """
      defmodule Example do
        def foo({a, b}), do: a + b
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == input
    end

    test "underscore without bind" do
      input = """
      defmodule Example do
        def foo(_), do: :ignored
      end
      """

      assert fix(NoRedundantUnderscoreBind, input) == input
    end

    test "regular assignment" do
      input = """
      x = 1
      """

      assert fix(NoRedundantUnderscoreBind, input) == input
    end
  end
end
