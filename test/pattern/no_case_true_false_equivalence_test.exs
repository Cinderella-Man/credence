defmodule Credence.Pattern.NoCaseTrueFalseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `case bool do true -> a; false -> b end` → `if bool, do: a, else: b`.
  The `true`/`false` clauses require a boolean subject, so the `if` is exactly
  equivalent. Input set drives the boolean both ways.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCaseTrueFalse

  test "case bool true/false → if/else preserves the branch" do
    assert_equivalent(
      """
      case x > 0 do
        true -> :pos
        false -> :nonpos
      end
      """,
      rule: NoCaseTrueFalse,
      vars: [:x],
      inputs: [1, -1, 0, 5, -5]
    )
  end
end
