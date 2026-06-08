defmodule Credence.Pattern.NoStringConcatInLoopEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.reduce(list, "", fn char, acc -> acc <> char end)` →
  `Enum.join(list)`. Both concatenate in order. Input set covers empty, single, and
  multi-element string lists.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoStringConcatInLoop

  test "reduce(acc <> char) → Enum.join preserves the concatenation" do
    assert_equivalent(
      """
      Enum.reduce(graphemes, "", fn char, acc -> acc <> char end)
      """,
      rule: NoStringConcatInLoop,
      vars: [:graphemes],
      inputs: [[], ["x"], ["a", "b", "c"], ["", "z", ""], ["日", "本"]]
    )
  end
end
