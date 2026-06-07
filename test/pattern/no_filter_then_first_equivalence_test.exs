defmodule Credence.Pattern.NoFilterThenFirstEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.at(Stream.filter(nums, pred), 0)` → `Enum.find(nums, pred)`.
  Both return the first element satisfying `pred` (or `nil`), applying `pred` in
  order and short-circuiting. Input set covers match, no-match, and empty.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoFilterThenFirst

  test "Enum.at(Stream.filter(nums, pred), 0) → Enum.find(nums, pred) preserves the first match" do
    assert_equivalent("Enum.at(Stream.filter(nums, fn x -> rem(x, 2) == 0 end), 0)",
      rule: NoFilterThenFirst,
      vars: [:nums],
      inputs: [[], [1, 3, 5], [1, 2, 3, 4], [2, 4], [-3, -2, -1]]
    )
  end
end
