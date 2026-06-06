defmodule Credence.Pattern.NoIdentityFunctionInEnumEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoIdentityFunctionInEnum

  # Firing snippets lifted from no_identity_function_in_enum_check_test.exs:
  #   defmodule Example do
  #       def run(list), do: Enum.uniq_by(list, fn x -> x end)
  #     end
  #   defmodule Example do
  #       def run(list), do: Enum.sort_by(list, fn item -> item end)
  #     end
  #   defmodule Example do
  #       def run(list), do: Enum.min_by(list, fn x -> x end)
  #     end

  test "no_identity_function_in_enum: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoIdentityFunctionInEnum,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
