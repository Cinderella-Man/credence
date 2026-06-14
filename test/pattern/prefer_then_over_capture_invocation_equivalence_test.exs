defmodule Credence.Pattern.PreferThenOverCaptureInvocationEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `value |> (&body).()` → `value |> then(&body)`.

  Both apply the capture to the piped value exactly once, so the result
  is identical. The capture must use exactly &1 (arity 1) for the rule
  to fire; captures using &2+ or no &N at all are left alone.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferThenOverCaptureInvocation

  test "palindrome capture: |> (&(&1 == String.reverse(&1))).() → then(&)" do
    assert_equivalent(
      "number |> Integer.to_string() |> (&(&1 == String.reverse(&1))).()",
      rule: PreferThenOverCaptureInvocation,
      vars: [:number],
      inputs: [1, 121, 123, 0, 12_321, 1001, 42, -5, 1000]
    )
  end

  test "simple arithmetic capture: |> (&(&1 + 1)).() → then(&)" do
    assert_equivalent(
      "x |> (&(&1 + 1)).()",
      rule: PreferThenOverCaptureInvocation,
      vars: [:x],
      inputs: [0, 1, -1, 42, 100, -999]
    )
  end

  test "bare identity capture: |> (& &1).() → then(& &1)" do
    assert_equivalent(
      "x |> (& &1).()",
      rule: PreferThenOverCaptureInvocation,
      vars: [:x],
      inputs: [0, 1, -1, "hello", :ok, [1, 2, 3]]
    )
  end
end
