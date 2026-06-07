defmodule Credence.Pattern.NoSortThenAtEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), empty-collection dimension.

  `Enum.sort(nums) |> Enum.at(0)` → `Enum.min(nums, fn -> nil end)` (and the
  `at(-1)` / `Enum.max` variants). The original returns `nil` on an empty
  collection; bare `Enum.min/1` would raise `Enum.EmptyError`, so the fix uses
  the `empty_fallback` to preserve `nil`-on-empty. The input set leads with `[]`
  and includes ties and the `1`/`1.0` value-kind case.

  Regression note: the bare-`Enum.min/1` fix diverged here (nil vs raise on `[]`);
  see docs/07. This test pins the empty-safe form.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoSortThenAt

  test "sort |> at(0) → Enum.min(_, fn -> nil end) preserves behaviour incl. empty list" do
    assert_equivalent("Enum.sort(nums) |> Enum.at(0)",
      rule: NoSortThenAt,
      vars: [:nums],
      inputs: B.term_lists()
    )
  end

  test "sort |> at(-1) → Enum.max(_, fn -> nil end) preserves behaviour incl. empty list" do
    assert_equivalent("Enum.sort(nums) |> Enum.at(-1)",
      rule: NoSortThenAt,
      vars: [:nums],
      inputs: B.term_lists()
    )
  end
end
