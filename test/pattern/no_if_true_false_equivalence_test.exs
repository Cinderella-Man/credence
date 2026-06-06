defmodule Credence.Pattern.NoIfTrueFalseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoIfTrueFalse

  # Firing snippets lifted from no_if_true_false_check_test.exs:
  #   def check(x) do
  #       if x > 0 do
  #         true
  #       else
  #         false
  #       end
  #     end
  #   def check(list) do
  #       if Enum.all?(list, &valid?/1) do
  #         true
  #       else
  #         false
  #       end
  #     end
  #   def check(parts) do
  #       if match?([_, _, _, _], parts) and Enum.all?(parts, &valid_octet?/1) do
  #         true
  #       else
  #         false
  #       end
  #     end

  test "no_if_true_false: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoIfTrueFalse,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
