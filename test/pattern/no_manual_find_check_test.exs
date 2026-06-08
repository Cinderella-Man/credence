defmodule Credence.Pattern.NoManualFindCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualFind

  describe "flags the manual find pattern" do
    test "arity 1 with a literal default" do
      code = """
      defmodule Bad do
        defp find_positive([]), do: -1
        defp find_positive([h | _t]) when h > 0, do: h
        defp find_positive([_h | t]), do: find_positive(t)
      end
      """

      [issue] = check(NoManualFind, code)
      assert issue.rule == :no_manual_find
      assert issue.message =~ "defp find_positive/1"
      assert issue.message =~ "Enum.find/3"
    end

    test "arity 2 threading a default parameter" do
      code = """
      defmodule Bad do
        defp find_first([], default), do: default
        defp find_first([h | _t], _default) when h > 0, do: h
        defp find_first([_h | t], default), do: find_first(t, default)
      end
      """

      [issue] = check(NoManualFind, code)
      assert issue.message =~ "defp find_first/2"
    end

    test "public def" do
      code = """
      defmodule Bad do
        def find_positive([]), do: nil
        def find_positive([h | _]) when h > 0, do: h
        def find_positive([_ | t]), do: find_positive(t)
      end
      """

      [issue] = check(NoManualFind, code)
      assert issue.message =~ "def find_positive/1"
    end

    test "clauses in a different order" do
      code = """
      defmodule Bad do
        defp find([h | _t]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
        defp find([]), do: nil
      end
      """

      [issue] = check(NoManualFind, code)
      assert issue.message =~ "find/1"
    end

    test "is_* guard over the head" do
      code = """
      defmodule Bad do
        defp first_atom([]), do: nil
        defp first_atom([h | _]) when is_atom(h), do: h
        defp first_atom([_ | t]), do: first_atom(t)
      end
      """

      assert [_issue] = check(NoManualFind, code)
    end

    test "compound boolean guard over the head" do
      code = """
      defmodule Bad do
        defp find([]), do: -1
        defp find([h | _]) when is_integer(h) and h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      assert [_issue] = check(NoManualFind, code)
    end

    test "negative-number and empty-list literal defaults" do
      neg = """
      defmodule Bad do
        defp find([]), do: -7
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      empty = """
      defmodule Bad do
        defp find([]), do: []
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      assert [_] = check(NoManualFind, neg)
      assert [_] = check(NoManualFind, empty)
    end
  end

  describe "does not flag — structural mismatches" do
    test "an existing Enum.find/3 call" do
      code = """
      defmodule Good do
        def find_odd(list), do: Enum.find(list, -1, &(rem(&1, 2) != 0))
      end
      """

      assert check(NoManualFind, code) == []
    end

    test "match clause without a guard" do
      code = """
      defmodule Good do
        defp find([]), do: nil
        defp find([:target | _]), do: :found
        defp find([_ | t]), do: find(t)
      end
      """

      assert check(NoManualFind, code) == []
    end

    test "match clause transforms the head" do
      code = """
      defmodule Good do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h * 2
        defp find([_ | t]), do: find(t)
      end
      """

      assert check(NoManualFind, code) == []
    end

    test "recurse clause calls a different function" do
      code = """
      defmodule Good do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: other(t)
      end
      """

      assert check(NoManualFind, code) == []
    end

    test "arity 3" do
      code = """
      defmodule Good do
        defp find([], a, _b), do: a
        defp find([h | _], _a, _b) when h > 0, do: h
        defp find([_ | t], a, b), do: find(t, a, b)
      end
      """

      assert check(NoManualFind, code) == []
    end

    test "2-clause function" do
      code = """
      defmodule Good do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h
      end
      """

      assert check(NoManualFind, code) == []
    end

    test "4-clause function" do
      code = """
      defmodule Good do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h
        defp find([h | _]) when h < -10, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      assert check(NoManualFind, code) == []
    end

    test "base case is not an empty list" do
      code = """
      defmodule Good do
        defp find([single]), do: single
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      assert check(NoManualFind, code) == []
    end

    test "base case body is a recursive call" do
      code = """
      defmodule Good do
        defp find([]), do: find([0])
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      assert check(NoManualFind, code) == []
    end
  end

  describe "does not flag — deliberately dropped unsafe/uncertain cases" do
    # A guard that can raise (rem/1 on a non-integer) is SKIPPED in the
    # multi-clause form but would RAISE as an Enum.find/3 predicate — a
    # different answer. Not flagged.
    test "raising guard" do
      code = """
      defmodule Skip do
        defp find_odd([]), do: -1
        defp find_odd([h | _t]) when rem(h, 2) != 0, do: h
        defp find_odd([_h | t]), do: find_odd(t)
      end
      """

      assert check(NoManualFind, code) == []
    end

    # The guard compares the head to the second parameter (a "target"). The
    # safe collapse would need to thread that var into the predicate; this
    # rule does not (guard vars must be the head only). Not flagged.
    test "guard references the second parameter" do
      code = """
      defmodule Skip do
        defp find([], _target), do: nil
        defp find([h | _], target) when h == target, do: h
        defp find([_ | t], target), do: find(t, target)
      end
      """

      assert check(NoManualFind, code) == []
    end

    # An arity-1 default that is an arbitrary expression would be evaluated
    # eagerly as an Enum.find/3 default argument, but the base clause runs
    # only when the list is exhausted. Not flagged.
    test "non-literal default expression (arity 1)" do
      code = """
      defmodule Skip do
        defp find([]), do: compute_default()
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      assert check(NoManualFind, code) == []
    end

    # An arity-2 base that returns a literal instead of threading its default
    # parameter is conservatively dropped (base must return its own param).
    test "arity 2 base returns a literal, not the parameter" do
      code = """
      defmodule Skip do
        defp find([], _d), do: nil
        defp find([h | _], _d) when h > 0, do: h
        defp find([_ | t], d), do: find(t, d)
      end
      """

      assert check(NoManualFind, code) == []
    end

    # A match-clause body with a side effect before returning the head would
    # be lost by the predicate-based rewrite. Not flagged.
    test "match clause body has a side effect" do
      code = """
      defmodule Skip do
        defp find([]), do: -1
        defp find([h | _]) when h > 0 do
          IO.inspect(h)
          h
        end
        defp find([_ | t]), do: find(t)
      end
      """

      assert check(NoManualFind, code) == []
    end

    # A recurse-clause body with a side effect before the self-call would be
    # lost by the rewrite. Not flagged.
    test "recurse clause body has a side effect" do
      code = """
      defmodule Skip do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]) do
          log(t)
          find(t)
        end
      end
      """

      assert check(NoManualFind, code) == []
    end
  end
end
