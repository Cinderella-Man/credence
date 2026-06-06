defmodule Credence.Pattern.NoCaseDestructureInPipeEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCaseDestructureInPipe

  # Firing snippets lifted from no_case_destructure_in_pipe_check_test.exs:
  #   defmodule BadCase do
  #       def process(x) do
  #         x
  #         |> compute()
  #         |> case do
  #           value -> value + 1
  #         end
  #       end
  #     end
  #   defmodule BadCase do
  #       def process(x) do
  #         x
  #         |> compute()
  #         |> case do
  #           _ -> 42
  #         end
  #       end
  #     end
  #   defmodule BadCase do
  #       def process(x) do
  #         x
  #         |> compute()
  #         |> case do
  #           _value -> 42
  #         end
  #       end
  #     end

  test "no_case_destructure_in_pipe: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoCaseDestructureInPipe,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
