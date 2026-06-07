defmodule Credence.Pattern.NoManualCountWithPredicateCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualCountWithPredicate

  describe "3-clause guard pattern — flagged" do
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

      [issue] = check(NoManualCountWithPredicate, code)
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

      [issue] = check(NoManualCountWithPredicate, code)
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

      [issue] = check(NoManualCountWithPredicate, code)
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

      [issue] = check(NoManualCountWithPredicate, code)
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

      [issue] = check(NoManualCountWithPredicate, code)
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

      [issue] = check(NoManualCountWithPredicate, code)
      assert issue.message =~ "count_above/3"
    end

    test "detects a safe boolean-combined guard (and over comparisons)" do
      code = """
      defmodule Bad do
        defp cnt([], _n, acc), do: acc
        defp cnt([h | t], n, acc) when h > 0 and h < n, do: cnt(t, n, acc + 1)
        defp cnt([_h | t], n, acc), do: cnt(t, n, acc)
      end
      """

      [issue] = check(NoManualCountWithPredicate, code)
      assert issue.message =~ "cnt/3"
    end
  end

  describe "2-clause if pattern — flagged" do
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

      [issue] = check(NoManualCountWithPredicate, code)
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

      [issue] = check(NoManualCountWithPredicate, code)
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

      [issue] = check(NoManualCountWithPredicate, code)
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

      [issue] = check(NoManualCountWithPredicate, code)
      assert issue.message =~ "tally/2"
    end
  end

  describe "no issue — non-count shapes" do
    test "does not flag Enum.count/2 calls" do
      code = """
      defmodule Good do
        def count(list, target), do: Enum.count(list, &(&1 == target))
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag when base case does not return accumulator" do
      code = """
      defmodule Good do
        defp count([], _target, acc), do: acc + 1
        defp count([h | t], target, acc) when h == target, do: count(t, target, acc + 1)
        defp count([_h | t], target, acc), do: count(t, target, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag when increment is not by 1" do
      code = """
      defmodule Good do
        defp sum_match([], _target, acc), do: acc
        defp sum_match([h | t], target, acc) when h == target, do: sum_match(t, target, acc + h)
        defp sum_match([_h | t], target, acc), do: sum_match(t, target, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag when skip clause also increments" do
      code = """
      defmodule Good do
        defp walk([], _target, acc), do: acc
        defp walk([h | t], target, acc) when h == target, do: walk(t, target, acc + 1)
        defp walk([_h | t], target, acc), do: walk(t, target, acc + 1)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag when guarded clause does not recurse" do
      code = """
      defmodule Good do
        defp find([], _target, acc), do: acc
        defp find([h | _t], target, _acc) when h == target, do: h
        defp find([_h | t], target, acc), do: find(t, target, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag when guard-triple arity is not 3" do
      code = """
      defmodule Good do
        defp count([], acc), do: acc
        defp count([h | t], acc) when h > 0, do: count(t, acc + 1)
        defp count([_h | t], acc), do: count(t, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
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

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag when guarded clause has no guard" do
      code = """
      defmodule Good do
        defp count([], _target, acc), do: acc
        defp count([h | t], target, acc), do: count(t, target, acc + 1)
        defp count([_h | t], target, acc), do: count(t, target, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag when base case is not empty list" do
      code = """
      defmodule Good do
        defp count([single], _target, acc), do: acc + 1
        defp count([h | t], target, acc) when h == target, do: count(t, target, acc + 1)
        defp count([_h | t], target, acc), do: count(t, target, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
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

      assert check(NoManualCountWithPredicate, code) == []
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

      assert check(NoManualCountWithPredicate, code) == []
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

      assert check(NoManualCountWithPredicate, code) == []
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

      assert check(NoManualCountWithPredicate, code) == []
    end
  end

  # ---- Deliberately-dropped UNSAFE cases (locked in as "no issue") ----
  #
  # These match the original (too-eager) detection but have no
  # behaviour-preserving collapse, so the narrowed rule must NOT flag them.

  describe "no issue — unsafe shapes the rule deliberately drops" do
    test "does not flag a guard that can raise (rem)" do
      # A guard silently SKIPS an element whose guard raises; the same
      # expression as an `Enum.count/2` predicate would RAISE. Different
      # answer on e.g. `[2, :a, 4]` (original returns a count, predicate
      # raises ArithmeticError), so this is dropped.
      code = """
      defmodule Good do
        defp count_even([], _n, acc), do: acc
        defp count_even([h | t], n, acc) when rem(h, 2) == 0, do: count_even(t, n, acc + 1)
        defp count_even([_h | t], n, acc), do: count_even(t, n, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag a guard with raising arithmetic operand" do
      code = """
      defmodule Good do
        defp cnt([], _n, acc), do: acc
        defp cnt([h | t], n, acc) when h + 1 > n, do: cnt(t, n, acc + 1)
        defp cnt([_h | t], n, acc), do: cnt(t, n, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag a guard with non-whitelisted call (hd)" do
      code = """
      defmodule Good do
        defp cnt([], _n, acc), do: acc
        defp cnt([h | t], n, acc) when hd(h) == n, do: cnt(t, n, acc + 1)
        defp cnt([_h | t], n, acc), do: cnt(t, n, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag guard-triple when the bound changes during recursion" do
      code = """
      defmodule Good do
        defp cnt([], _target, acc), do: acc
        defp cnt([h | t], target, acc) when h == target, do: cnt(t, target + 1, acc + 1)
        defp cnt([_h | t], target, acc), do: cnt(t, target, acc)
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag if-pattern when empty/cons positions differ" do
      code = """
      defmodule Good do
        defp cnt([], y, acc), do: acc
        defp cnt(y, [h | t], acc) do
          new_acc = if h > 0, do: acc + 1, else: acc
          cnt(y, t, new_acc)
        end
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end

    test "does not flag if-pattern when a bound changes during recursion" do
      code = """
      defmodule Good do
        defp cnt([], n, acc), do: acc
        defp cnt([h | t], n, acc) do
          new_acc = if h > n, do: acc + 1, else: acc
          cnt(t, n + 1, new_acc)
        end
      end
      """

      assert check(NoManualCountWithPredicate, code) == []
    end
  end
end
