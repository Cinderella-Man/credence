defmodule Credence.Pattern.NoTakeWhileLengthCheckEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `range |> Enum.take_while(pred) |> length() == n` → a `reduce_while` that counts
  matches and halts on the first false, compared to `n`. Both count the leading run
  of `pred`-true elements and short-circuit identically. Input set drives the
  predicate to pass-all, fail-early, and fail-first.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoTakeWhileLengthCheck

  @expr """
  half = div(len, 2)
  0..(half - 1)//1
  |> Enum.take_while(fn i -> Enum.at(g, i) == Enum.at(g, len - 1 - i) end)
  |> length() == half
  """

  test "take_while |> length == n → reduce_while count == n preserves the boolean" do
    assert_equivalent(@expr,
      rule: NoTakeWhileLengthCheck,
      vars: [:g, :len],
      inputs: [
        {["a", "b", "a"], 3},
        {["a", "b", "c"], 3},
        {["x", "x", "x", "x"], 4},
        {["a", "z", "b", "a"], 4},
        {[], 0}
      ]
    )
  end
end
