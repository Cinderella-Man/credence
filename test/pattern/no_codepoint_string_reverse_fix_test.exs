defmodule Credence.Pattern.NoCodepointStringReverseFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCodepointStringReverse

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoCodepointStringReverse, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix — codepoints → String.reverse" do
    test "fixes codepoints |> reverse |> IO.iodata_to_binary" do
      input = """
      def r(str), do: str |> String.codepoints() |> Enum.reverse() |> IO.iodata_to_binary()
      """

      expected = """
      def r(str), do: String.reverse(str)
      """

      assert fix(input) == expected
    end

    test "fixes codepoints |> reverse |> Enum.join" do
      input = """
      def r(str), do: str |> String.codepoints() |> Enum.reverse() |> Enum.join()
      """

      expected = """
      def r(str), do: String.reverse(str)
      """

      assert fix(input) == expected
    end

    test "fixes nested IO.iodata_to_binary(Enum.reverse(String.codepoints(...)))" do
      input = """
      def r(str), do: IO.iodata_to_binary(Enum.reverse(String.codepoints(str)))
      """

      expected = """
      def r(str), do: String.reverse(str)
      """

      assert fix(input) == expected
    end

    test "keeps upstream pipeline, replaces last steps" do
      input = """
      def r(str), do: str |> String.trim() |> String.codepoints() |> Enum.reverse() |> Enum.join()
      """

      expected = """
      def r(str), do: str |> String.trim() |> String.reverse()
      """

      assert fix(input) == expected
    end

    test "does not touch graphemes decompose" do
      code = """
      def r(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join()
      """

      assert fix(code) == code
    end

    test "does not touch Enum.join with separator" do
      code = """
      def r(str), do: str |> String.codepoints() |> Enum.reverse() |> Enum.join("-")
      """

      assert fix(code) == code
    end
  end
end
