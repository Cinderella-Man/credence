defmodule Credence.Pattern.PreferGraphemesForCharacterUniquenessPropertyTest do
  @moduledoc """
  The real safety proof for `prefer_graphemes_for_character_uniqueness` (decision
  6b): under the `single_codepoint_graphemes` promise, the original
  `String.to_charlist(s) |> Enum.uniq() |> Enum.count() |> (&(&1 == String.length(s))).()`
  and the rewrite
  `String.graphemes(s) |> Enum.uniq() |> Enum.count() |> then(&(&1 == String.length(s)))`
  agree across thousands of random promise-satisfying strings.

  Under the promise, every grapheme is exactly one codepoint, so
  `String.to_charlist/1` and `String.graphemes/1` produce lists of the same
  length and the uniqueness check yields the same result.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Credence.AssumptionGenerators

  property "old and fixed agree under the promise for single-codepoint strings" do
    check all(s <- AssumptionGenerators.single_codepoint_string()) do
      old =
        String.to_charlist(s)
        |> Enum.uniq()
        |> Enum.count()
        |> (&(&1 == String.length(s))).()

      fixed =
        String.graphemes(s)
        |> Enum.uniq()
        |> Enum.count()
        |> then(&(&1 == String.length(s)))

      assert old == fixed
    end
  end

  describe "known differences WITHOUT the promise (why the switch is necessary)" do
    test "decomposed accent: codepoint-count and grapheme-count disagree" do
      # NFD: "e" + combining acute U+0301
      nfd = :unicode.characters_to_nfd_binary("café")

      old =
        String.to_charlist(nfd)
        |> Enum.uniq()
        |> Enum.count()
        |> (&(&1 == String.length(nfd))).()

      fixed =
        String.graphemes(nfd)
        |> Enum.uniq()
        |> Enum.count()
        |> then(&(&1 == String.length(nfd)))

      # old is false (codepoints != graphemes), fixed is true (graphemes == graphemes)
      refute old == fixed
    end
  end
end
