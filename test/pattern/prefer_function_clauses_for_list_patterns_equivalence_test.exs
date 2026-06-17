defmodule Credence.Pattern.PreferFunctionClausesForListPatternsEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A function clause with `is_list(list)` guard and
  a `case list do ... end` body is rewritten to multiple function clauses
  with list patterns in the head. The dispatch is identical — `is_list`
  already guarantees the value is a list, so the case patterns are the
  only discriminating factor.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferFunctionClausesForListPatterns

  @before """
  defmodule Bad do
    def my_fun(list, k) when is_list(list) and is_integer(k) and k >= 0 do
      case list do
        [] -> 0
        [_single] -> 0
        [h | t] ->
          {min_v, max_v} =
            Enum.reduce(t, {h, h}, fn val, {min_val, max_val} ->
              {min(min_val, val), max(max_val, val)}
            end)

          diff = max_v - min_v
          result = diff - 2 * k
          if result < 0, do: 0, else: result
      end
    end
  end
  """

  test "case dispatch on list parameter preserves behaviour" do
    assert_equivalent_module(@before,
      rule: PreferFunctionClausesForListPatterns,
      call: {:my_fun, 2},
      inputs: [
        {[], 0},
        {[], 5},
        {[1], 0},
        {[1], 5},
        {[1, 5, 3], 0},
        {[1, 5, 3], 1},
        {[1, 5, 3], 10},
        {[3, 1, 2, 1, 3, 2], 2},
        {Enum.to_list(1..20), 5}
      ]
    )
  end

  # A guarded earlier sibling (`f([], k) when k < 0`) does not cover the `[] ->`
  # branch for non-negative k — the promoted `[]` head must be kept, or the
  # k >= 0 path would change answer.
  @guarded_sibling """
  defmodule Bad2 do
    def f([], k) when k < 0, do: :neg
    def f(list, k) when is_list(list) and is_integer(k) do
      case list do
        [] -> :b
        [h | t] -> {:cons, h, t}
      end
    end
  end
  """

  test "guarded earlier sibling preserves behaviour" do
    assert_equivalent_module(@guarded_sibling,
      rule: PreferFunctionClausesForListPatterns,
      call: {:f, 2},
      inputs: [
        {[], -1},
        {[], 0},
        {[], 7},
        {[1], 0},
        {[1, 2, 3], 4}
      ]
    )
  end
end
