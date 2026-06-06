defmodule Credence.Pattern.NoManualListReduceEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A manual `sum([], acc) -> acc; sum([h|t], acc) -> sum(t, f(acc, h))`
  fold collapses to `Enum.reduce/3`. The accumulator order and per-element update
  are preserved, so the result matches incl. the value-kind sum case.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualListReduce

  @before """
  defmodule Bad do
    def total(list), do: sum(list, 0)
    defp sum([], acc), do: acc
    defp sum([h | t], acc), do: sum(t, acc + h)
  end
  """

  test "manual fold recursion → Enum.reduce preserves the accumulated total" do
    assert_equivalent_module(@before,
      rule: NoManualListReduce,
      call: {:total, 1},
      inputs: [[], [1, 2, 3], [1.0, 2.0], [1, 1.0, 2], Enum.to_list(1..50)]
    )
  end
end
