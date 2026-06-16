defmodule Credence.Pattern.NoUnusedComputationEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). The rule removes a dead `_n = length(chars)` where the
  call is total on a provably-typed argument (`chars` is a list — bound to
  `String.graphemes/1`). Removing it is a block-statement change, observable only
  by compiling the before/after module and calling the surviving function.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoUnusedComputation

  @before """
  defmodule Bad do
    def run(s) do
      chars = String.graphemes(s)
      _n = length(chars)
      Enum.with_index(chars)
    end
  end
  """

  test "removing the dead total computation preserves run/1 behaviour" do
    assert_equivalent_module(@before,
      rule: NoUnusedComputation,
      call: {:run, 1},
      inputs: ["", "a", "abc", "héllo", "日本語"]
    )
  end
end
