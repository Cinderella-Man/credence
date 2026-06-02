defmodule Credence.Pattern.NoManualCountWithPredicateTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualCountWithPredicate

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualCountWithPredicate.check(ast, [])
  end

  describe "NoManualCountWithPredicate" do
    test "detects the exact hand-rolled count pattern" do
      code = """
      defmodule Bad do
        def wordcount(list, target) do
          do_count(list, target, 0)
        end

        defp do_count([], _target, acc), do: acc

        defp do_count([h | t], target, acc) when h == target do
          do_count(t, target, acc + 1)
        end

        defp do_count([_h | t], target, acc) do
          do_count(t, target, acc)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_count_with_predicate
      assert issue.message =~ "do_count/3"
      assert issue.message =~ "Enum.count"
    end

    test "detects with different function names" do
      code = """
      defmodule Bad do
        defp count_match([], _target, acc), do: acc
        defp count_match([h | t], target, acc) when h == target, do: count_match(t, target, acc + 1)
        defp count_match([_h | t], target, acc), do: count_match(t, target, acc)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "count_match/3"
    end

    test "detects with def (public) function" do
      code = """
      defmodule Bad do
        def my_count([], _target, acc), do: acc
        def my_count([h | t], target, acc) when h == target, do: my_count(t, target, acc + 1)
        def my_count([_h | t], target, acc), do: my_count(t, target, acc)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "def my_count/3"
    end

    test "detects with reversed acc + 1 order" do
      code = """
      defmodule Bad do
        defp tally([], _n, acc), do: acc
        defp tally([h | t], n, acc) when h == n, do: tally(t, n, 1 + acc)
        defp tally([_h | t], n, acc), do: tally(t, n, acc)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "tally/3"
    end

    test "detects with clauses in different order" do
      code = """
      defmodule Bad do
        defp cnt([_h | t], n, acc), do: cnt(t, n, acc)
        defp cnt([], _n, acc), do: acc
        defp cnt([h | t], n, acc) when h == n, do: cnt(t, n, acc + 1)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "cnt/3"
    end

    test "detects with inequality guard" do
      code = """
      defmodule Bad do
        defp count_above([], _threshold, acc), do: acc
        defp count_above([h | t], threshold, acc) when h > threshold,
          do: count_above(t, threshold, acc + 1)
        defp count_above([_h | t], threshold, acc),
          do: count_above(t, threshold, acc)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "count_above/3"
    end

    # ---- Negative cases ----

    test "does not flag Enum.count/2 calls" do
      code = """
      defmodule Good do
        def count(list, target), do: Enum.count(list, &(&1 == target))
      end
      """

      assert check(code) == []
    end

    test "does not flag when base case does not return accumulator" do
      code = """
      defmodule Good do
        defp count([], _target, acc), do: acc + 1
        defp count([h | t], target, acc) when h == target, do: count(t, target, acc + 1)
        defp count([_h | t], target, acc), do: count(t, target, acc)
      end
      """

      assert check(code) == []
    end

    test "does not flag when increment is not by 1" do
      code = """
      defmodule Good do
        defp sum_match([], _target, acc), do: acc
        defp sum_match([h | t], target, acc) when h == target, do: sum_match(t, target, acc + h)
        defp sum_match([_h | t], target, acc), do: sum_match(t, target, acc)
      end
      """

      assert check(code) == []
    end

    test "does not flag when skip clause also increments" do
      code = """
      defmodule Good do
        defp walk([], _target, acc), do: acc
        defp walk([h | t], target, acc) when h == target, do: walk(t, target, acc + 1)
        defp walk([_h | t], target, acc), do: walk(t, target, acc + 1)
      end
      """

      assert check(code) == []
    end

    test "does not flag when guarded clause does not recurse" do
      code = """
      defmodule Good do
        defp find([], _target, acc), do: acc
        defp find([h | _t], target, _acc) when h == target, do: h
        defp find([_h | t], target, acc), do: find(t, target, acc)
      end
      """

      assert check(code) == []
    end

    test "does not flag when arity is not 3" do
      code = """
      defmodule Good do
        defp count([], acc), do: acc
        defp count([h | t], acc) when h > 0, do: count(t, acc + 1)
        defp count([_h | t], acc), do: count(t, acc)
      end
      """

      assert check(code) == []
    end

    test "does not flag functions with more than 3 clauses" do
      code = """
      defmodule Good do
        defp count([], _target, acc), do: acc
        defp count([single], target, acc) when single == target, do: acc + 1
        defp count([single], _target, acc), do: acc
        defp count([h | t], target, acc) when h == target, do: count(t, target, acc + 1)
        defp count([_h | t], target, acc), do: count(t, target, acc)
      end
      """

      assert check(code) == []
    end

    test "does not flag when guarded clause has no guard" do
      code = """
      defmodule Good do
        defp count([], _target, acc), do: acc
        defp count([h | t], target, acc), do: count(t, target, acc + 1)
        defp count([_h | t], target, acc), do: count(t, target, acc)
      end
      """

      # The second clause has no guard — this is just unconditionally
      # incrementing for every element (i.e. length), not predicate counting.
      assert check(code) == []
    end

    test "does not flag when base case is not empty list" do
      code = """
      defmodule Good do
        defp count([single], _target, acc), do: acc + 1
        defp count([h | t], target, acc) when h == target, do: count(t, target, acc + 1)
        defp count([_h | t], target, acc), do: count(t, target, acc)
      end
      """

      assert check(code) == []
    end

    # ---- 2-clause if pattern ----

    test "detects 2-clause if-based count with arity 3" do
      code = """
      defmodule Bad do
        def count_below(list, threshold) do
          do_count(list, threshold, 0)
        end

        defp do_count(_bound, [], acc), do: acc

        defp do_count(bound, [head | tail], acc) do
          new_acc = if head < bound, do: acc + 1, else: acc
          do_count(bound, tail, new_acc)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_count_with_predicate
      assert issue.message =~ "do_count/3"
      assert issue.message =~ "Enum.count"
    end

    test "detects 2-clause if-based count with arity 2" do
      code = """
      defmodule Bad do
        defp count_positive([], acc), do: acc
        defp count_positive([h | t], acc) do
          new_acc = if h > 0, do: acc + 1, else: acc
          count_positive(t, new_acc)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "count_positive/2"
    end

    test "detects 2-clause if-based count with reversed clause order" do
      code = """
      defmodule Bad do
        defp do_count(bound, [head | tail], acc) do
          new_acc = if head < bound, do: acc + 1, else: acc
          do_count(bound, tail, new_acc)
        end

        defp do_count(_bound, [], acc), do: acc
      end
      """

      [issue] = check(code)
      assert issue.message =~ "do_count/3"
    end

    test "detects 2-clause if with reversed acc + 1" do
      code = """
      defmodule Bad do
        defp tally([], acc), do: acc
        defp tally([h | t], acc) do
          new_acc = if h > 0, do: 1 + acc, else: acc
          tally(t, new_acc)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "tally/2"
    end

    test "does not flag 2-clause if when do branch is not acc + 1" do
      code = """
      defmodule Good do
        defp sum_match([], acc), do: acc
        defp sum_match([h | t], acc) do
          new_acc = if h > 0, do: acc + h, else: acc
          sum_match(t, new_acc)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag 2-clause if when else branch is not acc" do
      code = """
      defmodule Good do
        defp weird([], acc), do: acc
        defp weird([h | t], acc) do
          new_acc = if h > 0, do: acc + 1, else: acc - 1
          weird(t, new_acc)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag 2-clause if when body has extra expressions" do
      code = """
      defmodule Good do
        defp count([], acc), do: acc
        defp count([h | t], acc) do
          new_acc = if h > 0, do: acc + 1, else: acc
          IO.puts(h)
          count(t, new_acc)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag 2-clause if when base case does not return acc" do
      code = """
      defmodule Good do
        defp count([], acc), do: acc + 1
        defp count([h | t], acc) do
          new_acc = if h > 0, do: acc + 1, else: acc
          count(t, new_acc)
        end
      end
      """

      assert check(code) == []
    end
  end
end
