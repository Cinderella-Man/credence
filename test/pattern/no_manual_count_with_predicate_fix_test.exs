defmodule Credence.Pattern.NoManualCountWithPredicateFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualCountWithPredicate

  describe "3-clause guard pattern — collapse to Enum.count/2" do
    test "canonical multi-clause count" do
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

      expected = """
      defmodule Bad do
        def wordcount(list, target) do
          do_count(list, target, 0)
        end

        defp do_count(list, target, acc) when is_list(list),
          do: acc + Enum.count(list, fn h -> h == target end)
      end
      """

      assert fix(NoManualCountWithPredicate, code) == expected
    end

    test "inequality guard, single-line clauses" do
      code = """
      defmodule Bad do
        defp count_above([], _threshold, acc), do: acc
        defp count_above([h | t], threshold, acc) when h > threshold,
          do: count_above(t, threshold, acc + 1)
        defp count_above([_h | t], threshold, acc),
          do: count_above(t, threshold, acc)
      end
      """

      expected = """
      defmodule Bad do
        defp count_above(list, threshold, acc) when is_list(list),
          do: acc + Enum.count(list, fn h -> h > threshold end)
      end
      """

      assert fix(NoManualCountWithPredicate, code) == expected
    end

    test "clauses in reversed order collapse at the first clause position" do
      code = """
      defmodule Bad do
        defp cnt([_h | t], n, acc), do: cnt(t, n, acc)
        defp cnt([], _n, acc), do: acc
        defp cnt([h | t], n, acc) when h == n, do: cnt(t, n, acc + 1)
      end
      """

      expected = """
      defmodule Bad do
        defp cnt(list, n, acc) when is_list(list), do: acc + Enum.count(list, fn h -> h == n end)
      end
      """

      assert fix(NoManualCountWithPredicate, code) == expected
    end
  end

  describe "2-clause if pattern — collapse to Enum.count/2" do
    test "arity 2" do
      code = """
      defmodule Bad do
        defp count_positive([], acc), do: acc
        defp count_positive([h | t], acc) do
          new_acc = if h > 0, do: acc + 1, else: acc
          count_positive(t, new_acc)
        end
      end
      """

      expected = """
      defmodule Bad do
        defp count_positive(list, acc) when is_list(list), do: acc + Enum.count(list, fn h -> h > 0 end)
      end
      """

      assert fix(NoManualCountWithPredicate, code) == expected
    end

    test "arity 3 with list in the middle position" do
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

      expected = """
      defmodule Bad do
        def count_below(list, threshold) do
          do_count(list, threshold, 0)
        end

        defp do_count(bound, list, acc) when is_list(list),
          do: acc + Enum.count(list, fn head -> head < bound end)
      end
      """

      assert fix(NoManualCountWithPredicate, code) == expected
    end

    test "reversed 1 + acc" do
      code = """
      defmodule Bad do
        defp tally([], acc), do: acc
        defp tally([h | t], acc) do
          new_acc = if h > 0, do: 1 + acc, else: acc
          tally(t, new_acc)
        end
      end
      """

      expected = """
      defmodule Bad do
        defp tally(list, acc) when is_list(list), do: acc + Enum.count(list, fn h -> h > 0 end)
      end
      """

      assert fix(NoManualCountWithPredicate, code) == expected
    end
  end

  describe "idempotency and no-ops" do
    test "the collapsed output is left unchanged on a second pass" do
      code = """
      defmodule Bad do
        defp do_count(list, target, acc) when is_list(list),
          do: acc + Enum.count(list, fn h -> h == target end)
      end
      """

      assert fix(NoManualCountWithPredicate, code) == code
    end

    test "leaves an unsafe (raising) guard untouched" do
      code = """
      defmodule Good do
        defp count_even([], _n, acc), do: acc
        defp count_even([h | t], n, acc) when rem(h, 2) == 0, do: count_even(t, n, acc + 1)
        defp count_even([_h | t], n, acc), do: count_even(t, n, acc)
      end
      """

      assert fix(NoManualCountWithPredicate, code) == code
    end

    test "leaves an existing Enum.count/2 call untouched" do
      code = """
      defmodule Good do
        def count(list, target), do: Enum.count(list, &(&1 == target))
      end
      """

      assert fix(NoManualCountWithPredicate, code) == code
    end
  end
end
