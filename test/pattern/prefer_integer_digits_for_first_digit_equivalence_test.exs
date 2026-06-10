defmodule Credence.Pattern.PreferIntegerDigitsForFirstDigitEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). The rewrite `number |> abs() |> to_string() |>
  String.first() |> String.to_integer()` → `number |> abs() |> Integer.digits()
  |> hd()` preserves the first-digit value.

  Both approaches extract the first digit of the absolute value of a number.
  Input set covers positive integers, negative integers, zero, and larger numbers.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferIntegerDigitsForFirstDigit

  test "rewrite preserves first digit extraction" do
    assert_equivalent(
      """
      number
      |> abs()
      |> to_string()
      |> String.first()
      |> String.to_integer()
      """,
      rule: PreferIntegerDigitsForFirstDigit,
      vars: [:number],
      inputs: [1, 42, 123, -5, -99, 100, 987_654_321]
    )
  end
end
