defmodule Credence.Pattern.PreferGraphemesForCharacterUniquenessFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferGraphemesForCharacterUniqueness

  test "rewrites the anti-pattern" do
    input = """
    def checkunique(string) when is_binary(string) do
      String.to_charlist(string)
      |> Enum.uniq()
      |> Enum.count()
      |> (&(&1 == String.length(string))).()
    end
    """

    expected = """
    def checkunique(string) when is_binary(string) do
      String.graphemes(string)
      |> Enum.uniq()
      |> Enum.count()
      |> then(&(&1 == String.length(string)))
    end
    """

    assert fix(PreferGraphemesForCharacterUniqueness, input) == expected
  end
end
