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

    test "repeated-variable head is not a catch-all (non-linear pattern)" do
      # `split_key(_binary, start, start)` only matches when args 2 and 3 are
      # equal, so the next clause is reachable. Flagging it would delete live
      # code (real example: plug's Plug.Conn.Query.split_key/3).
      code = """
      defmodule Good do
        defp split_key(_binary, start, start), do: nil
        defp split_key(binary, current, start), do: binary_part(binary, start, current - start)
      end
      """

      assert clean?(RemoveUnreachableClausesAfterCatchall, code)
    end

    test "guarded clause after catch-all is left alone (dead by position, not a duplicate)" do
      # The guarded clause matches a NARROWER domain than the catch-all, so it is
      # dead only because of its position — likely an ordering bug. Deleting it
      # masks the bug; reordering changes dispatch (the original always returns 0,
      # a reordered version computes a value for list inputs). Neither is
      # behaviour-preserving, so we touch nothing.
      code = """
      defmodule Solution do
        def car_fleets(_target, _positions, _speeds) do
          0
        end

        def car_fleets(target, positions, speeds) when is_list(positions) and is_list(speeds) do
          Enum.zip(positions, speeds)
          |> Enum.sort_by(fn {pos, _speed} -> -pos end)
          |> Enum.map(fn {pos, speed} -> (target - pos) / speed end)
          |> Enum.count()
        end
      end
      """

      assert clean?(RemoveUnreachableClausesAfterCatchall, code)
    end

    test "pattern clause after catch-all is left alone (dead by position, not a duplicate)" do
      # `count(_str, "")` and the guarded `count(_str, char)` match narrower
      # domains than the catch-all `count(_str, _char)`; they are dead only
      # because of ordering. Removing them would change behaviour, so the rule
      # leaves the group untouched.
      code = """
      defmodule M do
        def count(_str, _char) do
          :catchall
        end

        def count(_str, "") do
          0
        end

        def count(_str, char) when byte_size(char) != 1 do
          0
        end
      end
      """

      assert clean?(RemoveUnreachableClausesAfterCatchall, code)
    end

    test "bodiless function head is not a catch-all" do
      # `def code(integer_or_atom)` declares default args / attaches docs; it
      # generates no clause and matches nothing, so the real clauses below stay
      # reachable (real example: plug's Plug.Conn.Status.code/1).
      code = """
      defmodule Good do
        def code(integer_or_atom)

        def code(integer) when integer in 100..999, do: integer
        def code(_other), do: nil
      end
      """

      assert clean?(RemoveUnreachableClausesAfterCatchall, code)
    end
  end
end
