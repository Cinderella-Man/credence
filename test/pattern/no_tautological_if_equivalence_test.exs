defmodule Credence.Pattern.NoTautologicalIfEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoTautologicalIf

  # Firing snippets lifted from no_tautological_if_check_test.exs:
  #   defp do_pass(list) do
  #       {swapped, result} = do_pass_recursive(list, false, [])
  #       if swapped do
  #         result
  #       else
  #         result
  #       end
  #     end
  #   def check(x) do
  #       if x > 0 do
  #         process(x)
  #       else
  #         process(x)
  #       end
  #     end
  #   def check(x) do
  #       if x > 0, do: value, else: value
  #     end

  test "no_tautological_if: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoTautologicalIf,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
