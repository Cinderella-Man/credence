defmodule Credence.Pattern.RedundantListGuardPropertyTest do
  @moduledoc """
  The safety proof for `redundant_list_guard`: under the `proper_lists` promise,
  whenever `[head | tail]` matches, `tail` is itself a list — so a
  `when is_list(tail)` guard is always true and removing it cannot change which
  clause matches. Verified across thousands of random proper lists.

  The "without the promise" cases pin down *why* the switch is necessary: on an
  improper list the tail is a non-list, the guard is false, and removing it
  changes behaviour.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Credence.AssumptionGenerators

  property "for proper non-empty lists, the cons tail is always a list (guard is redundant)" do
    check all(list <- AssumptionGenerators.proper_list()) do
      [_head | tail] = list
      assert is_list(tail)
    end
  end

  describe "known differences WITHOUT the promise (why the switch is necessary)" do
    test "improper list: the cons tail is a non-list, so is_list(tail) is false" do
      [_head | tail] = [1 | 2]
      refute is_list(tail)
    end

    test "removing the guard re-routes an improper list (the divergence the switch prevents)" do
      with_guard = fn
        [first | rest] when is_list(rest) -> {:matched, first, rest}
        _ -> :fallthrough
      end

      without_guard = fn
        [first | rest] -> {:matched, first, rest}
        _ -> :fallthrough
      end

      # proper list: identical
      assert with_guard.([1, 2]) == without_guard.([1, 2])
      # improper list: diverges — exactly what `proper_lists` promises away
      assert with_guard.([1 | 2]) == :fallthrough
      assert without_guard.([1 | 2]) == {:matched, 1, 2}
    end
  end
end
