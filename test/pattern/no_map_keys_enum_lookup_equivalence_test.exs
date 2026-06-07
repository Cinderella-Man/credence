defmodule Credence.Pattern.NoMapKeysEnumLookupEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `Map.keys(m) |> Enum.all?(fn k -> ...lookup... end)` → `Enum.all?(m, fn {k, v} -> ... end)`.
  Fires only on order-independent terminals (`all?`/`any?`), so the differing
  iteration order between `Map.keys/1` and direct map traversal (for >32-key maps)
  doesn't affect the boolean. Input set includes a 40-key map.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapKeysEnumLookup

  @expr "Map.keys(word_freqs) |> Enum.all?(fn char -> Map.get(letter_freqs, char, 0) >= word_freqs[char] end)"

  test "Map.keys |> Enum.all?(lookup) → direct map all? preserves the boolean" do
    assert_equivalent(@expr,
      rule: NoMapKeysEnumLookup,
      vars: [:word_freqs, :letter_freqs],
      inputs: [
        {%{"a" => 1}, %{"a" => 2}},
        {%{"a" => 3}, %{"a" => 1}},
        {%{}, %{}},
        {Map.new(1..40, &{&1, 1}), Map.new(1..40, &{&1, 5})}
      ]
    )
  end
end
