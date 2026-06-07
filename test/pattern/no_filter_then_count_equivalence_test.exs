defmodule Credence.Pattern.NoFilterThenCountEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `coll |> Enum.filter(pred) |> Enum.count()` → `Enum.count(coll, pred)`.
  Both apply the predicate once per element (same order) and count the matches.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoFilterThenCount

  test "filter(pred) |> count → Enum.count(coll, pred) preserves the count" do
    assert_equivalent("numbers |> Enum.filter(fn x -> rem(x, 2) == 0 end) |> Enum.count()",
      rule: NoFilterThenCount,
      vars: [:numbers],
      inputs: [[], [1, 2, 3, 4], [1, 3, 5], [2, 4, 6], Enum.to_list(-10..10)]
    )
  end
end
