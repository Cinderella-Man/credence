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

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, input), expected)
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

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, input), expected)
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

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, input), expected)
    end

    test "no-op when no catch-all is present" do
      code = """
      defmodule Good do
        def foo([], []), do: false
        def foo([h1 | t1], [h2 | t2]) when h1 == h2, do: foo(t1, t2)
        def foo(t1, t2), do: t1 == t2
      end
      """

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), code)
    end

    test "no-op when catch-all is the last clause" do
      code = """
      defmodule Good do
        def bar(x) when is_integer(x), do: x + 1
        def bar(_), do: 0
      end
      """

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), code)
    end

    # Regression (row 111548): removing trailing redundant catch-alls used to
    # re-render the whole module and swallow its closing `end` (non-compiling →
    # reverted). The merged-range delete keeps the module structure intact.
    test "removes two trailing redundant catch-alls, preserving the module end" do
      code = """
      defmodule M do
        def count(_str, _char) do
          :catchall
        end

        def count(_str, _a) do
          0
        end

        def count(_str, _b) do
          1
        end
      end
      """

      expected = """
      defmodule M do
        def count(_str, _char) do
          :catchall
        end
      end
      """

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), expected)
    end

    # Narrowed out (was over_fire, row 113007): a catch-all followed by a GUARDED
    # clause is left untouched. The guarded clause is dead only because of its
    # position; deleting it masks a likely ordering bug and reordering changes
    # dispatch (the original always returns 0 — see the equivalence test). Neither
    # is behaviour-preserving, so the fix is a no-op.
    test "no-op: guarded clause after catch-all is left alone" do
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

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), code)
    end

    # Narrowed out: a catch-all followed by literal/pattern clauses is left alone.
    # `count(_str, "")` matches a narrower domain than the catch-all, so it is
    # dead only by position — removing it would change behaviour.
    test "no-op: pattern clauses after catch-all are left alone" do
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

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), code)
    end
  end

  # Dynamic head names (`def unquote(op)(...)`) are unidentifiable, so the rule
  # must never delete one as a phantom duplicate. Previously it grouped distinct
  # macro-generated functions by `{nil, arity}` and deleted live clauses.
  describe "leaves dynamically-named (unquote) clauses untouched" do
    test "no-op: vix shape (def calls a defp, both unquote-named, same arity)" do
      code = """
      defmodule M do
        for {op, name} <- @ops do
          def unquote(op)(a, b) do
            unquote(name)(a, b)
          end

          defp unquote(name)(a, b) do
            a + b
          end
        end
      end
      """

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), code)
    end

    test "no-op: propcheck shape (sibling unquote defs, two share arity 3)" do
      code = """
      defmodule M do
        def unquote(pre)(_state, _call), do: true
        def unquote(next)(state, _call, _result), do: state
        def unquote(post)(_state, _call, _res), do: true
        def unquote(args)(_state), do: []
      end
      """

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), code)
    end

    test "no-op: two dynamic catch-alls of the same arity" do
      code = """
      defmodule M do
        def unquote(a)(_x, _y), do: 1
        def unquote(b)(_x, _y), do: 2
      end
      """

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), code)
    end
  end

  describe "real duplicates still removed when dynamic clauses are present" do
    test "removes the genuine duplicate, leaves the dynamic clause" do
      input = """
      defmodule M do
        def unquote(a)(_x, _y), do: 1

        def real(_x, _y), do: 2
        def real(_x, _y), do: 3
      end
      """

      expected = """
      defmodule M do
        def unquote(a)(_x, _y), do: 1

        def real(_x, _y), do: 2
      end
      """

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, input), expected)
    end

    # Conservative edge: a dynamic clause BETWEEN two real catch-alls breaks
    # their adjacency, so the duplicate is not removed. Safe (we never delete a
    # reachable clause); documented as a deliberate non-fix.
    test "no-op: real duplicate separated from its catch-all by a dynamic clause" do
      code = """
      defmodule M do
        def real(_x, _y), do: 1
        def unquote(a)(_x, _y), do: 2
        def real(_x, _y), do: 3
      end
      """

      confirm_fix(fix(RemoveUnreachableClausesAfterCatchall, code), code)
    end
  end
end
