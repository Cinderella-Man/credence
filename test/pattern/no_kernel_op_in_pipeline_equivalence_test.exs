defmodule Credence.Pattern.NoKernelOpInPipelineEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `score |> Kernel.>=(threshold)` → `score >= threshold`:
  the piped `Kernel.>=/2` is the infix operator. Input set drives the comparison
  true, false, and equal.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoKernelOpInPipeline

  test "score |> Kernel.>=(threshold) → score >= threshold preserves the boolean" do
    assert_equivalent("score |> Kernel.>=(threshold)",
      rule: NoKernelOpInPipeline,
      vars: [:score, :threshold],
      inputs: [{5, 3}, {3, 5}, {5, 5}, {-1, 0}, {1.0, 1}]
    )
  end
end
