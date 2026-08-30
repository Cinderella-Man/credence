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

    confirm_fix(fix(PreferGraphemesForCharacterUniqueness, input), expected)
  end

  test "does not rewrite a different operation between to_charlist and count" do
    input = """
    defmodule PreferGraphemesCharacterUniquenessFilterInput do
      if String.to_charlist("a")
         |> Enum.filter(&is_integer/1)
         |> Enum.count()
         |> (&(&1 == 1)).(),
         do: IO.warn("same result")
    end
    """

    control =
      String.replace(
        input,
        "PreferGraphemesCharacterUniquenessFilterInput",
        "PreferGraphemesCharacterUniquenessFilterControl"
      )

    emitted = fix(PreferGraphemesForCharacterUniqueness, input)

    assert clean?(PreferGraphemesForCharacterUniqueness, input)
    confirm_fix(emitted, input)
    assert compile_messages(emitted) == {:ok, ["same result"]}
    assert compile_messages(control) == {:ok, ["same result"]}
  end

  defp compile_messages(source) do
    case Credence.RuleHelpers.compile_and_capture(source) do
      {:ok, diagnostics} -> {:ok, Enum.map(diagnostics, & &1.message)}
      {:error, diagnostics} -> {:error, Enum.map(diagnostics, & &1.message)}
    end
  end
end
