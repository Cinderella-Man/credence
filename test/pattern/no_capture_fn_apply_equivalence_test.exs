defmodule Credence.Pattern.NoCaptureFnApplyEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). An immediately-applied capture `(& &1 + &2).(a, b)` → `a + b`:
  inlining the capture body with the actual arguments. Input set drives the args,
  including a value-kind pair.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCaptureFnApply

  test "(& &1 + &2).(a, b) → a + b preserves value+type" do
    assert_equivalent("(& &1 + &2).(a, b)",
      rule: NoCaptureFnApply,
      vars: [:a, :b],
      inputs: [{1, 2}, {3, 4}, {1.0, 2}, {-5, 5}, {0, 0}]
    )
  end
end
