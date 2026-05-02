defmodule Credence.Rule.NoGraphemePalindromeCheckTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoGraphemePalindromeCheck.check(ast, [])
  end

  describe "NoGraphemePalindromeCheck" do
    test "passes code that compares strings directly with String.reverse" do
      code = """
      defmodule GoodPalindrome do
        def is_palindrome(s) do
          cleaned = s |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
          cleaned == String.reverse(cleaned)
        end
      end
      """

      assert check(code) == []
    end

    test "detects graphemes == Enum.reverse(graphemes)" do
      code = """
      defmodule BadPalindrome do
        def is_palindrome(s) when is_binary(s) do
          normalized = s |> String.downcase() |> String.replace(~r/\\W/, "")
          graphemes = String.graphemes(normalized)
          graphemes == Enum.reverse(graphemes)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_grapheme_palindrome_check

      assert issue.message =~ "String.reverse"
      assert issue.meta.line != nil
    end

    test "detects charlist == Enum.reverse(charlist) via String.to_charlist" do
      code = """
      defmodule BadCharlist do
        def is_palindrome(s) when is_binary(s) do
          codepoints = String.to_charlist(s)
          codepoints == Enum.reverse(codepoints)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_grapheme_palindrome_check
    end

    test "detects pipe chain ending in String.graphemes then reverse compare" do
      code = """
      defmodule BadPipePalindrome do
        def is_palindrome(s) when is_binary(s) do
          normalized =
            s
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]/u, "")
            |> String.graphemes()

          normalized == Enum.reverse(normalized)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_grapheme_palindrome_check
    end

    test "ignores Enum.reverse used for non-palindrome purposes" do
      code = """
      defmodule SafeReverse do
        def reverse_graphemes(s) do
          graphemes = String.graphemes(s)
          Enum.reverse(graphemes)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores list reverse comparison when not from graphemes" do
      code = """
      defmodule SafeCompare do
        def is_palindrome_list(list) do
          list == Enum.reverse(list)
        end
      end
      """

      assert check(code) == []
    end
  end
end
