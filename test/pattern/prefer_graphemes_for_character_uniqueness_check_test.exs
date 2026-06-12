defmodule Credence.Pattern.PreferGraphemesForCharacterUniquenessCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferGraphemesForCharacterUniqueness

  test "flags the anti-pattern" do
    assert flagged?(PreferGraphemesForCharacterUniqueness, """
           def checkunique(string) when is_binary(string) do
             String.to_charlist(string)
             |> Enum.uniq()
             |> Enum.count()
             |> (&(&1 == String.length(string))).()
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferGraphemesForCharacterUniqueness, """
           def checkunique(string) when is_binary(string) do
             String.graphemes(string)
             |> Enum.uniq()
             |> Enum.count()
             |> then(&(&1 == String.length(string)))
           end
           """)
  end
end
