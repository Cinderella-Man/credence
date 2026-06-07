defmodule Credence.Pattern.NoListFoldEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), eval-order dimension.

  `List.foldl(list, acc, fun)` → `Enum.reduce(list, acc, fun)` (same left-to-right
  order). `List.foldr(list, acc, fun)` → `Enum.reduce(Enum.reverse(list), acc, fun)`
  — the fix reverses the list to preserve `foldr`'s right-to-left order, which a
  bare `Enum.reduce` would not. Both directions verified over lists.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoListFold

  test "List.foldl → Enum.reduce preserves accumulation (left-to-right)" do
    assert_equivalent("List.foldl(list, 0, fn x, acc -> acc + x end)",
      rule: NoListFold,
      vars: [:list],
      inputs: B.signed_integers()
    )
  end

  test "List.foldr → Enum.reduce(Enum.reverse(...)) preserves order (right-to-left)" do
    assert_equivalent("List.foldr(list, [], fn x, acc -> [x * 2 | acc] end)",
      rule: NoListFold,
      vars: [:list],
      inputs: B.signed_integers()
    )
  end
end
