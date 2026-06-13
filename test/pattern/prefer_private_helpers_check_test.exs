defmodule Credence.Pattern.PreferPrivateHelpersCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPrivateHelpers

  test "flags a public helper with @doc only used internally" do
    assert flagged?(PreferPrivateHelpers, """
    defmodule Solution do
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      @doc "Translates a single note."
      def translate_note("C#"), do: "H"
      def translate_note(note), do: note
    end
    """)
  end

  test "flags a public helper with @doc and @spec only used internally" do
    assert flagged?(PreferPrivateHelpers, """
    defmodule Solution do
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      @doc "Translates a single note."
      @spec translate_note(String.t()) :: String.t()
      def translate_note("C#"), do: "H"
      def translate_note(note), do: note
    end
    """)
  end

  test "flags a public helper with @spec only (no @doc) only used internally" do
    assert flagged?(PreferPrivateHelpers, """
    defmodule Solution do
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      @spec translate_note(String.t()) :: String.t()
      def translate_note("C#"), do: "H"
      def translate_note(note), do: note
    end
    """)
  end

  test "leaves public API function alone" do
    assert clean?(PreferPrivateHelpers, """
    defmodule Solution do
      @doc "Translates a list of notes."
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      defp translate_note(note), do: note
    end
    """)
  end

  test "leaves annotated function alone when it has no @doc or @spec" do
    assert clean?(PreferPrivateHelpers, """
    defmodule Solution do
      def musical_code(notes) do
        Enum.map(notes, &translate_note/1)
      end

      def translate_note(note), do: note
    end
    """)
  end

  test "leaves annotated function alone when called externally" do
    assert clean?(PreferPrivateHelpers, """
    defmodule Solution do
      @doc "Translates a single note."
      def translate_note("C#"), do: "H"
      def translate_note(note), do: note
    end
    """)
  end
end
