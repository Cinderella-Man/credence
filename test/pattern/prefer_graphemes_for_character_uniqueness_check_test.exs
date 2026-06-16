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

  test "flags the one-line form" do
    assert flagged?(
             PreferGraphemesForCharacterUniqueness,
             "String.to_charlist(s) |> Enum.uniq() |> Enum.count() |> (&(&1 == String.length(s))).()"
           )
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

  # --- boundary cases: the pattern is precise about each link in the chain ---

  test "no issue without String.to_charlist in the pipeline" do
    assert clean?(
             PreferGraphemesForCharacterUniqueness,
             "String.graphemes(s) |> Enum.uniq() |> Enum.count() |> (&(&1 == String.length(s))).()"
           )
  end

  test "no issue when the capture body is not an equality comparison" do
    assert clean?(
             PreferGraphemesForCharacterUniqueness,
             "String.to_charlist(s) |> Enum.uniq() |> Enum.count() |> (&(&1 > String.length(s))).()"
           )
  end

  test "no issue when the count step carries a predicate (Enum.count/2)" do
    assert clean?(
             PreferGraphemesForCharacterUniqueness,
             "String.to_charlist(s) |> Enum.uniq() |> Enum.count(& &1) |> (&(&1 == String.length(s))).()"
           )
  end
end
