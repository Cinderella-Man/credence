defmodule Credence.Pattern.NoCodepointStringReverseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), assumption-gated rule.

  `str |> String.codepoints() |> Enum.reverse() |> Enum.join()` → `String.reverse(str)`.

  The original reverses **codepoints**; the fix reverses **graphemes**. They
  agree only when every grapheme is a single codepoint — exactly the rule's
  declared `single_codepoint_graphemes` assumption. This test proves BOTH:
  equivalence inside the assumption's domain, and that the suite *catches* the
  divergence outside it (the reason the assumption exists).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoCodepointStringReverse

  @expr "str |> String.codepoints() |> Enum.reverse() |> Enum.join()"

  test "preserves behaviour for single-codepoint graphemes (in-assumption domain)" do
    assert_equivalent(@expr,
      rule: NoCodepointStringReverse,
      vars: [:str],
      inputs: B.single_codepoint_strings()
    )
  end

  test "DIVERGES on multi-codepoint graphemes — the harness flags it (why the assumption exists)" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_equivalent(@expr,
        rule: NoCodepointStringReverse,
        vars: [:str],
        inputs: B.multi_codepoint_strings()
      )
    end
  end
end
