defmodule Credence.Pattern.NoListConcatWithRecursiveResultEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `def build([h | t]), do: [h] ++ build(t)` → `[h | build(t)]`.
  `[h] ++ rest` is exactly `[h | rest]`, so the constructed list is identical for
  every input (and avoids the per-step concat traversal).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListConcatWithRecursiveResult

  @before """
  defmodule Bad do
    def build([]), do: []
    def build([h | t]), do: [h] ++ build(t)
  end
  """

  test "[h] ++ build(t) → [h | build(t)] preserves the list" do
    assert_equivalent_module(@before,
      rule: NoListConcatWithRecursiveResult,
      call: {:build, 1},
      inputs: [[], [1], [1, 2, 3], [:a, :b, :c], Enum.to_list(1..20)]
    )
  end
end
