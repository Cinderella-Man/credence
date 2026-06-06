defmodule Credence.Pattern.NoCaptureFnApplyEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoCaptureFnApply

  # Firing snippets lifted from no_capture_fn_apply_check_test.exs:
  #   defmodule Good do
  #       def process(el, col) do
  #         Enum.at(el, col)
  #       end
  #     end
  #   defmodule Good do
  #       def process(x) do
  #         fun = fn y -> y * 2 end
  #         fun.(x)
  #       end
  #     end
  #   defmodule Good do
  #       def process(list) do
  #         (&Enum.map/2).(list, &(&1 + 1))
  #       end
  #     end

  test "no_capture_fn_apply: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoCaptureFnApply,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
