defmodule Credence.Pattern.NoRedundantListTraversalEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Separate `Enum.min(list)` and `Enum.max(list)` over the same
  list (two traversals) collapse to one `Enum.min_max(list)`. `Enum.min_max/1` uses
  the same comparison as `min`/`max`, so the pair matches — including the value-kind
  `[1, 1.0]` case — and the empty list raises in both (`Enum.EmptyError`).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantListTraversal

  @before """
  defmodule Bad do
    def run(numbers) do
      minimum = Enum.min(numbers)
      maximum = Enum.max(numbers)
      {minimum, maximum}
    end
  end
  """

  test "separate Enum.min + Enum.max → Enum.min_max preserves {min, max} incl. value-kind/empty" do
    assert_equivalent_module(@before,
      rule: NoRedundantListTraversal,
      call: {:run, 1},
      inputs: [[3, 1, 2], [1, 1.0], [5], [], [-1, -5, 3], Enum.to_list(1..20)]
    )
  end
end
