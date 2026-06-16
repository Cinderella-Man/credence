defmodule Credence.Pattern.PreferCountsForLengthEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `length(String.codepoints(string))` →
  `Enum.sum(Map.values(counts))` when `counts` is already the frequency map
  from `string |> String.codepoints() |> Enum.frequencies()`.

  Both compute the total number of codepoints in the string. Input set covers
  empty, plain ASCII, precomposed accent (1 codepoint), and multi-codepoint
  emoji to witness Unicode correctness.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferCountsForLength

  test "length(String.codepoints(...)) → Enum.sum(Map.values(counts)) preserves n" do
    assert_equivalent(
      """
      counts = string |> String.codepoints() |> Enum.frequencies()
      n = length(String.codepoints(string))
      n
      """,
      rule: PreferCountsForLength,
      vars: [:string],
      inputs: ["", "abc", "hello", "café", "👨‍👩‍👧"]
    )
  end
end
