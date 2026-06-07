defmodule Credence.Pattern.NoSortForTopKEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), empty-collection dimension.

  After narrowing, the rule only rewrites the `Enum.at(0)` terminal:
  `Enum.sort(list) |> Enum.at(0)` → `Enum.min(list, fn -> nil end)` and
  `Enum.sort(list) |> Enum.reverse() |> Enum.at(0)` → `Enum.max(list, fn -> nil end)`.

  Regression note: the original rule also mapped `take(1)` (list vs scalar) and
  `hd` (ArgumentError vs Enum.EmptyError on `[]`) to `Enum.min` — both
  behaviour-changing — and used bare `Enum.min/1` which raised on `[]`. Those
  shapes are no longer fixed, and the `at(0)` shapes now use the empty_fallback.
  Input set leads with `[]`.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoSortForTopK

  test "sort |> at(0) → Enum.min(_, fn -> nil end) preserves behaviour incl. empty list" do
    assert_equivalent("Enum.sort(list) |> Enum.at(0)",
      rule: NoSortForTopK,
      vars: [:list],
      inputs: B.term_lists()
    )
  end

  test "sort |> reverse |> at(0) → Enum.max(_, fn -> nil end) preserves behaviour incl. empty list" do
    assert_equivalent("Enum.sort(list) |> Enum.reverse() |> Enum.at(0)",
      rule: NoSortForTopK,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
