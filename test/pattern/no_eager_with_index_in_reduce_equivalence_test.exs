defmodule Credence.Pattern.NoEagerWithIndexInReduceEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `Enum.reduce(Enum.with_index(list), acc, fn {val, idx}, a -> ... end)`
  is rewritten to thread the index without the eager `Enum.with_index/1` materialisation.
  The same `{val, idx}` pairs are folded in the same order, so the result is identical.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoEagerWithIndexInReduce

  @before """
  defmodule Bad do
    def process(list) do
      Enum.reduce(Enum.with_index(list), [], fn {val, idx}, acc -> [{idx, val} | acc] end)
    end
  end
  """

  test "reduce over with_index → index-threading reduce preserves the result" do
    assert_equivalent_module(@before,
      rule: NoEagerWithIndexInReduce,
      call: {:process, 1},
      inputs: [[], [5], [10, 20, 30], [:a, :b], Enum.to_list(1..15)]
    )
  end
end
