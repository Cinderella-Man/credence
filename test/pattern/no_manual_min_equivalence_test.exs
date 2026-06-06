defmodule Credence.Pattern.NoManualMinEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoManualMin

  # Firing snippets lifted from no_manual_min_check_test.exs:
  #   defmodule Bad do
  #       def smaller(a, b) do
  #         if a < b, do: a, else: b
  #       end
  #     end
  #   defmodule Bad do
  #       def smaller(a, b) do
  #         if a <= b, do: a, else: b
  #       end
  #     end
  #   defmodule Bad do
  #       def smaller(a, b) do
  #         if b > a, do: a, else: b
  #       end
  #     end

  test "no_manual_min: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoManualMin,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
