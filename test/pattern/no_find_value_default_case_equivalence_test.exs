defmodule Credence.Pattern.NoFindValueDefaultCaseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `case Enum.find_value(list, f) do nil -> d; v -> v end` → `Enum.find_value(list, d, f)`.
  The 3-arg `find_value` returns the default `d` exactly when the 2-arg form
  returns `nil`. Input set covers found, not-found, and empty.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoFindValueDefaultCase

  @expr """
  case Enum.find_value(list, fn x -> x > 2 && x end) do
    nil -> :default
    v -> v
  end
  """

  test "find_value + case-nil-default → find_value/3 preserves the result" do
    assert_equivalent(@expr,
      rule: NoFindValueDefaultCase,
      vars: [:list],
      inputs: [[], [1, 2], [1, 2, 3], [3, 4], [0, 0]]
    )
  end
end
