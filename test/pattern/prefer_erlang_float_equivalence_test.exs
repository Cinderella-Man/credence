defmodule Credence.Pattern.PreferErlangFloatEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.PreferErlangFloat

  # Firing snippets lifted from prefer_erlang_float_check_test.exs:
  #   {n * 1.0, Enum.sum(xs) * 1.0}
  #   {n * 1.0, Enum.sum(xs) * 1.0, m + 0.0}
  #   {1.0 * n, Enum.sum(xs) * 1.0}

  test "prefer_erlang_float: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: PreferErlangFloat,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
