defmodule Credence.Pattern.HallucinatedGuardEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.HallucinatedGuard

  # Firing snippets lifted from hallucinated_guard_check_test.exs:
  #   defmodule M do
  #       def f(x) when is_pos_integer(x), do: x
  #     end
  #   defmodule M do
  #       def f(x) when is_non_neg_integer(x), do: x
  #     end
  #   defmodule M do
  #       def f(x) when is_neg_integer(x), do: x
  #     end

  test "hallucinated_guard: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: HallucinatedGuard,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
