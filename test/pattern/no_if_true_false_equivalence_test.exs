defmodule Credence.Pattern.NoIfTrueFalseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `if cond do true else false end` → `cond` — safe because
  the rule fires only when the condition is already boolean (a comparison), so
  returning it directly equals the if/else. Battery drives the condition both ways.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIfTrueFalse

  test "if x > 0 do true else false end → (x > 0) preserves the boolean" do
    assert_equivalent("if x > 0 do\n  true\nelse\n  false\nend",
      rule: NoIfTrueFalse,
      vars: [:x],
      inputs: [1, -1, 0, 100, -100]
    )
  end
end
