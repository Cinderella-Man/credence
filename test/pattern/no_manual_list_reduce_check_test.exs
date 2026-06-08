defmodule Credence.Pattern.NoManualListReduceCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualListReduce

  describe "flagged — manual recursive folds" do
    test "canonical arity-2 sum" do
      code = """
      defmodule Bad do
        def total(list), do: sum(list, 0)
        defp sum([], acc), do: acc
        defp sum([h | t], acc), do: sum(t, acc + h)
      end
      """

      [issue] = check(NoManualListReduce, code)
      assert issue.rule == :no_manual_list_reduce
      assert issue.message =~ "sum/2"
      assert issue.message =~ "Enum.reduce"
    end

    test "arity-3 with a threaded-through parameter" do
      code = """
      defmodule Bad do
        defp scale([], _factor, acc), do: acc
        defp scale([h | t], factor, acc), do: scale(t, factor, acc + h * factor)
      end
      """

      [issue] = check(NoManualListReduce, code)
      assert issue.message =~ "scale/3"
    end

    test "public def function" do
      code = """
      defmodule Bad do
        def sum([], acc), do: acc
        def sum([h | t], acc), do: sum(t, acc + h)
      end
      """

      [issue] = check(NoManualListReduce, code)
      assert issue.message =~ "def sum/2"
    end

    test "clauses in reversed order" do
      code = """
      defmodule Bad do
        defp sum([h | t], acc), do: sum(t, acc + h)
        defp sum([], acc), do: acc
      end
      """

      [issue] = check(NoManualListReduce, code)
      assert issue.message =~ "sum/2"
    end

    test "update expression referencing the head and accumulator both ways" do
      code = """
      defmodule Bad do
        defp build([], acc), do: acc
        defp build([h | t], acc), do: build(t, [h | acc])
      end
      """

      [issue] = check(NoManualListReduce, code)
      assert issue.message =~ "build/2"
    end

    test "update that ignores the head (drop-style fold)" do
      code = """
      defmodule Bad do
        defp count([], acc), do: acc
        defp count([_h | t], acc), do: count(t, acc + 1)
      end
      """

      [issue] = check(NoManualListReduce, code)
      assert issue.message =~ "count/2"
    end
  end

  describe "no issue — shapes that are not the safe fold" do
    test "does not flag an existing Enum.reduce/3 call" do
      code = """
      defmodule Good do
        def sum(list), do: Enum.reduce(list, 0, fn h, acc -> acc + h end)
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag when the base does not return the accumulator" do
      code = """
      defmodule Good do
        defp sum([], _acc), do: 0
        defp sum([h | t], acc), do: sum(t, acc + h)
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag when the base pattern is not an empty list" do
      code = """
      defmodule Good do
        defp sum([x], acc), do: acc + x
        defp sum([h | t], acc), do: sum(t, acc + h)
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag a three-clause function" do
      code = """
      defmodule Good do
        defp sum([], acc), do: acc
        defp sum([0 | t], acc), do: sum(t, acc)
        defp sum([h | t], acc), do: sum(t, acc + h)
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag arity-1 functions" do
      code = """
      defmodule Good do
        defp last([x]), do: x
        defp last([_h | t]), do: last(t)
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag when the accumulator is not the last parameter" do
      code = """
      defmodule Good do
        defp sum(acc, []), do: acc
        defp sum(acc, [h | t]), do: sum(acc + h, t)
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag when a threaded parameter changes during recursion" do
      code = """
      defmodule Good do
        defp sum([], _n, acc), do: acc
        defp sum([h | t], n, acc), do: sum(t, n + 1, acc + h)
      end
      """

      assert check(NoManualListReduce, code) == []
    end
  end

  # ---- Deliberately-dropped UNSAFE cases (locked in as "no issue") ----
  #
  # These look like manual folds but have no behaviour-preserving collapse to
  # `Enum.reduce/3`, so the narrowed rule must NOT flag them.

  describe "no issue — unsafe shapes the rule deliberately drops" do
    test "does not flag when the update reads the tail" do
      # The reducer sees only the element and accumulator; `t` (the remaining
      # tail) is out of scope, so an update that reads it cannot be reproduced.
      code = """
      defmodule Good do
        defp f([], acc), do: acc
        defp f([h | t], acc), do: f(t, acc ++ [h | t])
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag a multi-statement recursive body" do
      # A side effect before the recursive call would be dropped or moved by a
      # reducer that only carries the accumulator update.
      code = """
      defmodule Good do
        defp f([], acc), do: acc
        defp f([h | t], acc) do
          IO.inspect(h)
          f(t, acc + h)
        end
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag a repeated-variable head (equality-constraint match)" do
      # `f([acc | t], acc)` matches only when head == acc; the collapse cannot
      # reproduce that and would emit `fn acc, acc -> ... end`.
      code = """
      defmodule Good do
        defp f([], acc), do: acc
        defp f([acc | t], acc), do: f(t, acc)
      end
      """

      assert check(NoManualListReduce, code) == []
    end

    test "does not flag a multi-statement base body" do
      code = """
      defmodule Good do
        defp f([], acc) do
          IO.inspect(:done)
          acc
        end

        defp f([h | t], acc), do: f(t, acc + h)
      end
      """

      assert check(NoManualListReduce, code) == []
    end
  end
end
