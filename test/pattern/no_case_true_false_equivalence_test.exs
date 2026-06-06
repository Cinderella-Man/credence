defmodule Credence.Pattern.NoCaseTrueFalseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoCaseTrueFalse

  # Firing snippets lifted from no_case_true_false_check_test.exs:
  #   valid_digits?()
  #     |> case do
  #       true -> :ok
  #       false -> :error
  #     end
  #   number
  #     |> Integer.digits()
  #     |> valid_digits?()
  #     |> case do
  #       true -> :valid
  #       false -> :invalid
  #     end
  #   check(x)
  #     |> case do
  #       true ->
  #         value = process(x)
  #         {:ok, value}
  #       false ->
  #         {:error, :failed}
  #     end

  test "no_case_true_false: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoCaseTrueFalse,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
