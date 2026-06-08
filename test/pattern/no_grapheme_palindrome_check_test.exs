defmodule Credence.Pattern.NoGraphemePalindromeCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoGraphemePalindrome
  alias Credence.Issue

  describe "check" do
    test "passes code that compares strings directly with String.reverse" do
      code = """
      defmodule GoodPalindrome do
        def is_palindrome(s) do
          cleaned = s |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
          cleaned == String.reverse(cleaned)
        end
      end
      """

      assert check(NoGraphemePalindrome, code) == []
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

      issues = check(NoGraphemePalindrome, code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_grapheme_palindrome

      assert issue.message =~ "String.reverse"
      assert issue.meta.line != nil
    end

    test "does NOT flag the String.to_charlist form (codepoint vs grapheme diverge)" do
      # Charlists index codepoints; String.reverse reverses graphemes. The two
      # diverge on multi-codepoint graphemes, so this form must be left alone.
      code = """
      defmodule MaybeCharlist do
        def is_palindrome(s) when is_binary(s) do
          codepoints = String.to_charlist(s)
          codepoints == Enum.reverse(codepoints)
        end
      end
      """

      assert check(NoGraphemePalindrome, code) == []
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

      issues = check(NoGraphemePalindrome, code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_grapheme_palindrome
    end

    test "fires when a bare-variable graphemes list is also used elsewhere" do
      code = """
      defmodule BadButUsed do
        def info(s) do
          graphemes = String.graphemes(s)
          {graphemes == Enum.reverse(graphemes), Enum.count(graphemes)}
        end
      end
      """

      assert length(check(NoGraphemePalindrome, code)) == 1
    end

    test "does NOT fire for a pipe-built variable that is used elsewhere" do
      # No behaviour-preserving single-expression rewrite exists: inlining the
      # pipe would duplicate it, and rebinding to the raw string would break
      # the other (list) use.
      code = """
      defmodule MaybePipe do
        def info(s) do
          normalized = s |> String.downcase() |> String.graphemes()
          {normalized == Enum.reverse(normalized), Enum.count(normalized)}
        end
      end
      """

      assert check(NoGraphemePalindrome, code) == []
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

      assert check(NoGraphemePalindrome, code) == []
    end

    test "ignores list reverse comparison when not from graphemes" do
      code = """
      defmodule SafeCompare do
        def is_palindrome_list(list) do
          list == Enum.reverse(list)
        end
      end
      """

      assert check(NoGraphemePalindrome, code) == []
    end
  end
end
