defmodule Credence.Pattern.NoRedundantBinarySyntaxEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `<<"hello">>` → `"hello"`. A bitstring literal wrapping a
  single string segment is exactly that string; no free vars.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantBinarySyntax

  test "<<\"hello\">> → \"hello\" is the same binary" do
    assert_equivalent(
      """
      <<"hello">>
      """,
      rule: NoRedundantBinarySyntax,
      vars: [],
      inputs: [nil],
      allow_few_inputs: true
    )
  end
end
