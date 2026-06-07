defmodule Credence.Pattern.NoEnumCountForLengthEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), enumerable-type dimension.

  `Enum.count(<list>)` → `length(<list>)`, where the argument is **provably a
  list** (a list-returning call or a pipe ending in one). `length/1` only accepts
  lists, so the rule is narrowed to never fire on a bare variable (which might be
  a range/map/stream where `length/1` would raise). On a real list the two are
  identical.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoEnumCountForLength

  test "Enum.count(list-returning call) → length(...) preserves the count" do
    assert_equivalent("Enum.count(Enum.reverse(list))",
      rule: NoEnumCountForLength,
      vars: [:list],
      inputs: B.term_lists()
    )
  end

  test "pipe ending in a list-returning call: ... |> Enum.count() → ... |> length()" do
    assert_equivalent("list |> Enum.uniq() |> Enum.count()",
      rule: NoEnumCountForLength,
      vars: [:list],
      inputs: B.term_lists()
    )
  end
end
