defmodule Credence.Pattern.UnnecessaryGraphemeChunkingEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), bounds + Unicode dimension.

  `string |> String.graphemes() |> Enum.chunk_every(n, 1, :discard) |> Enum.map(&Enum.join/1)`
  → `for i <- 0..(String.length(string) - n)//1, do: String.slice(string, i, n)`.

  Regression note: the original fix omitted the `//1` step, so when the string
  was shorter than the chunk size the range descended (`0..-1` = `[0, -1]`) and
  emitted bogus slices instead of `[]` (see docs/07). The battery includes
  `len < n`, `len == n`, and a multi-codepoint grapheme string.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.UnnecessaryGraphemeChunking

  @expr "string |> String.graphemes() |> Enum.chunk_every(n, 1, :discard) |> Enum.map(&Enum.join/1)"

  test "grapheme chunking → for/String.slice preserves behaviour incl. len < n and Unicode" do
    assert_equivalent(@expr,
      rule: UnnecessaryGraphemeChunking,
      vars: [:string, :n],
      inputs: [
        {"abcde", 2},
        {"abc", 1},
        {"ab", 3},
        {"a", 2},
        {"", 2},
        {:unicode.characters_to_nfd_binary("café"), 2}
      ]
    )
  end
end
