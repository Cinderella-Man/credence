defmodule Credence.Pattern.PreferDescSortOverNegativeTakeEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), order-preservation dimension.

  `Enum.sort(nums) |> Enum.take(-3)` → `Enum.sort(nums, :desc) |> Enum.take(3) |> Enum.reverse()`.

  Regression note: the original fix omitted the trailing `Enum.reverse/1`, so it
  reversed the result order (n largest ascending vs descending) — see docs/07.
  The reverse restores the order, making the rewrite behaviour-preserving. The
  input set covers empty, ties, the `1`/`1.0` value-kind case, and fewer-than-n
  elements.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferDescSortOverNegativeTake

  test "sort |> take(-3) → desc sort + take + reverse preserves the result exactly" do
    assert_equivalent(
      "Enum.sort(nums) |> Enum.take(-3)",
      rule: PreferDescSortOverNegativeTake,
      vars: [:nums],
      inputs: [
        [],
        [1],
        [1, 2],
        [3, 1, 2, 1, 3, 2],
        [5, 4, 3, 2, 1],
        [1, 1.0, 2],
        Enum.to_list(1..20)
      ]
    )
  end
end
