defmodule Credence.Pattern.PreferExplicitBinaryArithmeticEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `String.length(input_string) |> rem(3)` → `rem(String.length(input_string), 3)`.
  Semantically identical — the pipe operator passes the left-hand side as the
  first argument, which is exactly what the explicit call does.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferExplicitBinaryArithmetic

  test "String.length(s) |> rem(3) preserves behaviour" do
    assert_equivalent(
      "String.length(input_string) |> rem(3)",
      rule: PreferExplicitBinaryArithmetic,
      vars: [:input_string],
      inputs: ["", "a", "hi", "hello", "world!", "abcdef"]
    )
  end

  test "x |> div(5) preserves behaviour" do
    assert_equivalent(
      "x |> div(5)",
      rule: PreferExplicitBinaryArithmetic,
      vars: [:x],
      inputs: [0, 1, 5, 10, 42, 100]
    )
  end
end
