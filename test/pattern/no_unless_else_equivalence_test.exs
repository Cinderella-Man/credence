defmodule Credence.Pattern.NoUnlessElseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `unless cond, do: a, else: b` → `if cond, do: b, else: a`
  (branches swapped). Input set drives the condition both ways.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoUnlessElse

  test "unless cond, do: a, else: b → if cond, do: b, else: a preserves the branch" do
    assert_equivalent("unless x > 0, do: :neg, else: :pos",
      rule: NoUnlessElse,
      vars: [:x],
      inputs: [1, -1, 0, 5, -5]
    )
  end
end
