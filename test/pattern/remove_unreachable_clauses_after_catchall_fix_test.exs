defmodule Credence.Pattern.RemoveUnreachableClausesAfterCatchallFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.RemoveUnreachableClausesAfterCatchall

  describe "fix/2" do
    test "removes unreachable clause after catch-all (spec example)" do
      input = """
      defmodule Solution do
        def exactly_one_replace([], []), do: false

        def exactly_one_replace([h1 | t1], [h2 | t2]) when h1 == h2 do
          exactly_one_replace(t1, t2)
        end

        def exactly_one_replace(t1, t2) do
          t1 == t2
        end

        def exactly_one_replace(_, _), do: false
      end
      """

      expected = """
      defmodule Solution do
        def exactly_one_replace([], []), do: false

        def exactly_one_replace([h1 | t1], [h2 | t2]) when h1 == h2 do
          exactly_one_replace(t1, t2)
        end

        def exactly_one_replace(t1, t2) do
          t1 == t2
        end
      end
      """

      assert fix(RemoveUnreachableClausesAfterCatchall, input) == expected
    end

    test "removes unreachable clause after catch-all with underscore args" do
      input = """
      defmodule Bad do
        def foo(x) do
          x + 1
        end

        def foo(_), do: 0
      end
      """

      expected = """
      defmodule Bad do
        def foo(x) do
          x + 1
        end
      end
      """

      assert fix(RemoveUnreachableClausesAfterCatchall, input) == expected
    end

    test "removes multiple unreachable clauses after catch-all" do
      input = """
      defmodule Bad do
        def baz(x), do: x
        def baz(_), do: nil
        def baz(_), do: false
      end
      """

      expected = """
      defmodule Bad do
        def baz(x), do: x
      end
      """

      assert fix(RemoveUnreachableClausesAfterCatchall, input) == expected
    end

    test "no-op when no catch-all is present" do
      code = """
      defmodule Good do
        def foo([], []), do: false
        def foo([h1 | t1], [h2 | t2]) when h1 == h2, do: foo(t1, t2)
        def foo(t1, t2), do: t1 == t2
      end
      """

      assert fix(RemoveUnreachableClausesAfterCatchall, code) == code
    end

    test "no-op when catch-all is the last clause" do
      code = """
      defmodule Good do
        def bar(x) when is_integer(x), do: x + 1
        def bar(_), do: 0
      end
      """

      assert fix(RemoveUnreachableClausesAfterCatchall, code) == code
    end
  end
end
