defmodule Credence.Pattern.NoCaseBooleanResultEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoCaseBooleanResult

  # Firing snippets lifted from no_case_boolean_result_check_test.exs:
  #   check(x)
  #     |> case do
  #       :ok -> true
  #       _ -> false
  #     end
  #   x
  #     |> validate()
  #     |> normalize()
  #     |> case do
  #       :ok -> true
  #       _ -> false
  #     end
  #   case result do
  #       :ok -> true
  #       _ -> false
  #     end

  test "no_case_boolean_result: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoCaseBooleanResult,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
