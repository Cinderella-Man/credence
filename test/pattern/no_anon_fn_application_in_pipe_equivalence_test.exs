defmodule Credence.Pattern.NoAnonFnApplicationInPipeEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoAnonFnApplicationInPipe

  # Firing snippets lifted from no_anon_fn_application_in_pipe_check_test.exs:
  #   (none auto-extracted — see the check test)

  test "no_anon_fn_application_in_pipe: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoAnonFnApplicationInPipe,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
