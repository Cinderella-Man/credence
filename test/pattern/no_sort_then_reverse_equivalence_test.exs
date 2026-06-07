defmodule Credence.Pattern.NoSortThenReverseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), sort-stability dimension.

  `x |> Enum.sort() |> Enum.reverse()` → `x |> Enum.sort(:desc)`.

  Run over lists with many equal elements: a stable sort keeps equal elements
  in input order, and `sort |> reverse` vs `sort(:desc)` must agree on the
  whole result (including the relative order of equal values).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoSortThenReverse

  test "sort |> reverse → sort(:desc) preserves ordering incl. ties" do
    assert_equivalent("x |> Enum.sort() |> Enum.reverse()",
      rule: NoSortThenReverse,
      vars: [:x],
      inputs: B.stability_lists()
    )
  end
end
