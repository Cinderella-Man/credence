defmodule Credence.Pattern.NoKernelOpInPipelineEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoKernelOpInPipeline

  # Firing snippets lifted from no_kernel_op_in_pipeline_check_test.exs:
  #   defmodule Example do
  #       def run(list) do
  #         list |> Enum.sort() |> Kernel.==(list)
  #       end
  #     end
  #   defmodule Example do
  #       def run(a, b), do: a |> String.downcase() |> Kernel.!=(b)
  #     end
  #   defmodule Example do
  #       def run(score, threshold), do: score |> calculate() |> Kernel.>=(threshold)
  #     end

  test "no_kernel_op_in_pipeline: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoKernelOpInPipeline,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
