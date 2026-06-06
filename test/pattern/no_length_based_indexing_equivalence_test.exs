defmodule Credence.Pattern.NoLengthBasedIndexingEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `n = length(list); Enum.at(list, n - 1)` → `List.last(list)`.
  `Enum.at(list, length(list) - 1)` is the last element; on `[]` it is
  `Enum.at(list, -1)` = `nil`, which matches `List.last([])` = `nil`. So they agree
  on every list incl. empty.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoLengthBasedIndexing

  @before """
  defmodule Bad do
    def run(list) do
      n = length(list)
      last = Enum.at(list, n - 1)
      last
    end
  end
  """

  test "Enum.at(list, length-1) → List.last preserves the last element incl. empty" do
    assert_equivalent_module(@before,
      rule: NoLengthBasedIndexing,
      call: {:run, 1},
      inputs: [[], [5], [1, 2, 3], [1, 1.0], [:a, :b, :c], Enum.to_list(1..20)]
    )
  end
end
