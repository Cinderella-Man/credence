defmodule Credence.Pattern.NoParamRebindingEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). Renames a local that rebinds a function parameter so the
  shadowing is explicit: `fn x, {count, acc} -> acc = [x | acc]; {count + 1, acc} end`
  → the inner `acc` becomes `new_acc`. A pure alpha-rename within the closure —
  behaviour identical for every input.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoParamRebinding

  @expr """
  Enum.reduce(arr, {0, []}, fn x, {count, acc} ->
    acc = [x | acc]
    {count + 1, acc}
  end)
  """

  test "renaming the rebound param preserves the reduce result" do
    assert_equivalent(@expr,
      rule: NoParamRebinding,
      vars: [:arr],
      inputs: [[], [1, 2, 3], [:a, :b], [1, 1.0]]
    )
  end
end
