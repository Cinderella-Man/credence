defmodule Credence.Pattern.RemoveUnreachableClausesAfterCatchallCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.RemoveUnreachableClausesAfterCatchall

  describe "flags unreachable clauses after catch-all" do
    test "flags clause after catch-all with bare variable args" do
      code = """
      defmodule Bad do
        def foo(x) do
          x + 1
        end

        def foo(_), do: 0
      end
      """

      [issue] = check(RemoveUnreachableClausesAfterCatchall, code)
      assert issue.rule == :remove_unreachable_clauses_after_catchall
      assert issue.meta.line == 6
    end

    test "flags clause after catch-all with underscore args" do
      code = """
      defmodule Bad do
        def bar(_, _), do: true
        def bar(x, y), do: x == y
      end
      """

      [issue] = check(RemoveUnreachableClausesAfterCatchall, code)
      assert issue.meta.line == 3
    end

    test "flags multiple unreachable clauses after catch-all" do
      code = """
      defmodule Bad do
        def baz(x), do: x
        def baz(_), do: nil
        def baz(_), do: false
      end
      """

      issues = check(RemoveUnreachableClausesAfterCatchall, code)
      assert length(issues) == 2
      assert Enum.at(issues, 0).meta.line == 3
      assert Enum.at(issues, 1).meta.line == 4
    end

    test "flags the spec example" do
      code = """
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

      [issue] = check(RemoveUnreachableClausesAfterCatchall, code)
      assert issue.rule == :remove_unreachable_clauses_after_catchall
      assert issue.meta.line == 12
    end
  end

  describe "leaves good code alone" do
    test "no catch-all clause present" do
      code = """
      defmodule Good do
        def foo([], []), do: false
        def foo([h1 | t1], [h2 | t2]) when h1 == h2, do: foo(t1, t2)
        def foo(t1, t2), do: t1 == t2
      end
      """

      assert clean?(RemoveUnreachableClausesAfterCatchall, code)
    end

    test "catch-all is the last (and only reachable) clause" do
      code = """
      defmodule Good do
        def bar(x) when is_integer(x), do: x + 1
        def bar(_), do: 0
      end
      """

      assert clean?(RemoveUnreachableClausesAfterCatchall, code)
    end

    test "guarded clause after catch-all is NOT unreachable (different arity)" do
      code = """
      defmodule Good do
        def foo(x), do: x
        def bar(y), do: y
      end
      """

      assert clean?(RemoveUnreachableClausesAfterCatchall, code)
    end
  end
end
