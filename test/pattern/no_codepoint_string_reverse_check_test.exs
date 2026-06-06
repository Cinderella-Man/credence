defmodule Credence.Pattern.NoCodepointStringReverseCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoCodepointStringReverse

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCodepointStringReverse.check(ast, [])
  end

  test "declares the single_codepoint_graphemes assumption" do
    assert NoCodepointStringReverse.assumptions() == [:single_codepoint_graphemes]
  end

  describe "check — detects codepoint decompose (both reassembles)" do
    test "codepoints |> reverse |> IO.iodata_to_binary pipeline" do
      code =
        ~s[def r(str), do: str |> String.codepoints() |> Enum.reverse() |> IO.iodata_to_binary()]

      assert [%Issue{rule: :no_codepoint_string_reverse}] = check(code)
    end

    test "codepoints |> reverse |> Enum.join pipeline" do
      code = ~s[def r(str), do: str |> String.codepoints() |> Enum.reverse() |> Enum.join()]
      assert [%Issue{rule: :no_codepoint_string_reverse}] = check(code)
    end

    test "nested IO.iodata_to_binary(Enum.reverse(String.codepoints(...)))" do
      code = ~s[def r(str), do: IO.iodata_to_binary(Enum.reverse(String.codepoints(str)))]
      assert [%Issue{rule: :no_codepoint_string_reverse}] = check(code)
    end

    test "nested Enum.join(Enum.reverse(String.codepoints(...)))" do
      code = ~s[def r(str), do: Enum.join(Enum.reverse(String.codepoints(str)))]
      assert [%Issue{rule: :no_codepoint_string_reverse}] = check(code)
    end

    test "keeps upstream pipeline before codepoints" do
      code = """
      str
      |> String.trim()
      |> String.codepoints()
      |> Enum.reverse()
      |> Enum.join()
      """

      assert [%Issue{rule: :no_codepoint_string_reverse}] = check(code)
    end
  end

  describe "check — does NOT flag" do
    test "graphemes decompose (handled by NoManualStringReverse)" do
      code = ~s[def r(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join()]
      assert check(code) == []
    end

    test "codepoints used without the reverse pattern" do
      assert check(~s[def r(s), do: s |> String.codepoints() |> length()]) == []
    end
  end
end
