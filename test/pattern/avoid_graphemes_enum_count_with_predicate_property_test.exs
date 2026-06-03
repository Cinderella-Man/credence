defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicatePropertyTest do
  @moduledoc """
  The real safety proof for `avoid_graphemes_enum_count_with_predicate` (decision
  6b): under the `single_codepoint_graphemes` promise, the original
  `String.graphemes(s) |> Enum.count(&(&1 == c))` and the rewrite
  `String.count(s, c)` agree across thousands of random promise-satisfying
  strings — for any single-codepoint literal `c`.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Credence.AssumptionGenerators

  # A single-codepoint character literal, drawn from the same safe ranges.
  defp single_codepoint_char do
    StreamData.string([?\s..?~, 0xC0..0xD6, 0xD8..0xF6, 0xF8..0xFF], length: 1)
  end

  property "old and fixed agree under the promise for any single-codepoint literal" do
    check all(
            s <- AssumptionGenerators.single_codepoint_string(),
            c <- single_codepoint_char()
          ) do
      old = String.graphemes(s) |> Enum.count(&(&1 == c))
      new = String.count(s, c)
      assert old == new
    end
  end

  describe "known differences WITHOUT the promise (why the switch is necessary)" do
    test "decomposed accent: grapheme-count and String.count disagree" do
      nfd = "e" <> <<0x301::utf8>>
      old = String.graphemes(nfd) |> Enum.count(&(&1 == "e"))
      new = String.count(nfd, "e")
      assert old == 0
      assert new == 1
      refute old == new
    end
  end
end
