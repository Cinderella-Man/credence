defmodule Credence.Pattern.PreferPrivateHelpersFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPrivateHelpers

  test "converts def to defp and removes @doc and @spec" do
    input = """
    defmodule Solution do
      @doc \"\"\"
      Translates a list of musical notes into a special code.

      Sharp notes (C#, D#, F#, G#, A#) are translated to H, I, J, K, L respectively.
      All other notes remain unchanged.
      \"\"\"
      @spec musical_code(list(String.t())) :: list(String.t())
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      @doc \"\"\"
      Translates a single musical note into its special code.
      \"\"\"
      @spec translate_note(String.t()) :: String.t()
      def translate_note("C#"), do: "H"
      def translate_note("D#"), do: "I"
      def translate_note("F#"), do: "J"
      def translate_note("G#"), do: "K"
      def translate_note("A#"), do: "L"
      def translate_note(note), do: note
    end
    """

    expected = """
    defmodule Solution do
      @doc \"\"\"
      Translates a list of musical notes into a special code.

      Sharp notes (C#, D#, F#, G#, A#) are translated to H, I, J, K, L respectively.
      All other notes remain unchanged.
      \"\"\"
      @spec musical_code(list(String.t())) :: list(String.t())
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      defp translate_note("C#"), do: "H"
      defp translate_note("D#"), do: "I"
      defp translate_note("F#"), do: "J"
      defp translate_note("G#"), do: "K"
      defp translate_note("A#"), do: "L"
      defp translate_note(note), do: note
    end
    """

    assert fix(PreferPrivateHelpers, input) == expected
  end

  test "converts def to defp removing @spec only (no @doc)" do
    input = """
    defmodule Solution do
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      @spec translate_note(String.t()) :: String.t()
      def translate_note("C#"), do: "H"
      def translate_note(note), do: note
    end
    """

    expected = """
    defmodule Solution do
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      defp translate_note("C#"), do: "H"
      defp translate_note(note), do: note
    end
    """

    assert fix(PreferPrivateHelpers, input) == expected
  end

  test "does not modify code with no anti-pattern" do
    code = """
    defmodule Solution do
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      defp translate_note(note), do: note
    end
    """

    assert fix(PreferPrivateHelpers, code) == code
  end

  test "round-trip: fixed code produces no issues" do
    code = """
    defmodule Solution do
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      @doc "Translates a single note."
      @spec translate_note(String.t()) :: String.t()
      def translate_note("C#"), do: "H"
      def translate_note(note), do: note
    end
    """

    assert check(PreferPrivateHelpers, fix(PreferPrivateHelpers, code)) == []
  end
end
