defmodule Credence.Pattern.NoIdentityFloatCoercionEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoIdentityFloatCoercion

  # Firing snippets lifted from no_identity_float_coercion_check_test.exs:
  #   defmodule Example do
  #       def foo(list), do: Enum.sum(list) * 1.0
  #       def bar(list), do: Enum.count(list) / 1.0
  #     end
  #   defmodule Example do
  #       def foo(a, b), do: (a + b) * 1.0
  #       def bar(list), do: Enum.sum(list) + 0.0
  #     end
  #   Enum.count(list) - 0.0

  test "no_identity_float_coercion: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoIdentityFloatCoercion,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
