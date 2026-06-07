defmodule Credence.Pattern.NoListPopAtForAccessEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `List.pop_at(list, 0)` returns `{popped, rest}`:
    * `|> elem(0)` (the popped head) → `List.first(list)`
    * `|> elem(1)` (the rest)        → `List.delete_at(list, 0)`
  Both forms verified incl. empty and single-element lists.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoListPopAtForAccess

  test "List.pop_at(list, 0) |> elem(0) → List.first(list)" do
    assert_equivalent("list |> List.pop_at(0) |> elem(0)",
      rule: NoListPopAtForAccess,
      vars: [:list],
      inputs: B.term_lists()
    )
  end

  test "List.pop_at(list, 0) |> elem(1) → List.delete_at(list, 0)" do
    assert_equivalent("list |> List.pop_at(0) |> elem(1)",
      rule: NoListPopAtForAccess,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
