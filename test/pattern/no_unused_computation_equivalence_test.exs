defmodule Credence.Pattern.NoUnusedComputationEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). The rule removes `_n = length(chars)` — a dead
  assignment to an underscore-prefixed variable whose RHS is the pure
  function `length/1`. Removing it does not change the function's return
  value for any input, because the assigned variable is never read.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoUnusedComputation

  @before """
  defmodule Example do
    def process(s) do
      chars = String.graphemes(s)
      _n = length(chars)

      chars
      |> Enum.with_index()
      |> Enum.into(%{}, fn {char, idx} -> {char, idx} end)
    end
  end
  """

  test "removing _n = length(chars) preserves behaviour" do
    assert_equivalent_module(@before,
      rule: NoUnusedComputation,
      call: {:process, 1},
      inputs: [
        "abc",
        "hello",
        "",
        "café",
        "👨‍👩‍👧"
      ]
    )
  end
end
