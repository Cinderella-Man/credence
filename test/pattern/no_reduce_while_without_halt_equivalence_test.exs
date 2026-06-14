defmodule Credence.Pattern.NoReduceWhileWithoutHaltEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).

  `Enum.reduce_while(list, acc, fn x, acc -> {:cont, ...} end)` → `Enum.reduce(...)`
  with the `{:cont, value}` unwrapped to `value`. When every callback returns
  `{:cont, _}` (never halts), `reduce_while` is exactly `reduce`. Verified over
  lists including empty and value-kind.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoReduceWhileWithoutHalt

  test "reduce_while (all :cont) → reduce preserves the accumulation" do
    assert_equivalent(
      "Enum.reduce_while(list, 0, fn x, acc -> {:cont, acc + x} end)",
      rule: NoReduceWhileWithoutHalt,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
