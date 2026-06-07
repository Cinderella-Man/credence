defmodule Credence.Pattern.NoManualStringReverseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), Unicode dimension — the always-safe sibling of
  `no_codepoint_string_reverse`.

  `str |> String.graphemes() |> Enum.reverse() |> Enum.join()` → `String.reverse(str)`.

  Both sides reverse by **grapheme**, so they agree on every string — including
  decomposed accents, ZWJ emoji, and flags. Unlike the codepoint variant, this
  needs no assumption: it passes over the full multi-codepoint input set.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoManualStringReverse

  test "graphemes |> reverse |> join → String.reverse preserves behaviour over all Unicode" do
    assert_equivalent("str |> String.graphemes() |> Enum.reverse() |> Enum.join()",
      rule: NoManualStringReverse,
      vars: [:str],
      inputs: B.unicode_strings()
    )
  end
end
