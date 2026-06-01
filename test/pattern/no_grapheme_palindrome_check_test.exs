defmodule Credence.Pattern.NoGraphemePalindromeCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoGraphemePalindromeCheck

  alias Credence.Issue
  alias NoGraphemePalindrome

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoGraphemePalindromeCheck.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoGraphemePalindromeCheck, code, [])

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

    test "detects graphemes mid-pipe followed by filter then reverse compare" do
      code = """
      defmodule BadMidPipePalindrome do
        def palindrome?(s) do
          cleaned =
            s
            |> String.downcase()
            |> String.graphemes()
            |> Enum.filter(fn c -> c in ?a..?z or c in ?0..?9 end)

          cleaned == Enum.reverse(cleaned)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_grapheme_palindrome_check
    end

    test "detects charlist mid-pipe followed by map then reverse compare" do
      code = """
      defmodule BadMidPipeCharlist do
        def palindrome?(s) do
          cleaned =
            s
            |> String.to_charlist()
            |> Enum.filter(fn c -> c in ?a..?z end)

          cleaned == Enum.reverse(cleaned)
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

    test "ignores when decompose var is used for other purposes besides palindrome check" do
      code = """
      defmodule SafeGraphemes do
        def check(s) do
          graphemes = String.graphemes(s)

          if not Enum.all?(graphemes, &only_alpha?/1) or
               not (graphemes == Enum.reverse(graphemes)) do
            false
          else
            true
          end
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "strips direct String.graphemes and replaces Enum.reverse with String.reverse" do
      code = """
      graphemes = String.graphemes(s)
      graphemes == Enum.reverse(graphemes)
      """

      result = fix(code)
      refute result =~ "String.graphemes"
      assert result =~ "String.reverse"
      refute result =~ "Enum.reverse"
    end

    test "strips direct String.to_charlist" do
      code = """
      chars = String.to_charlist(s)
      chars == Enum.reverse(chars)
      """

      result = fix(code)
      refute result =~ "String.to_charlist"
      assert result =~ "String.reverse"
    end

    test "strips terminal pipe stage for piped decomposition" do
      code = """
      normalized = s |> String.downcase() |> String.graphemes()
      normalized == Enum.reverse(normalized)
      """

      result = fix(code)
      assert result =~ "String.downcase"
      refute result =~ "String.graphemes"
      assert result =~ "String.reverse"
    end

    test "handles reversed comparison order" do
      code = """
      graphemes = String.graphemes(s)
      Enum.reverse(graphemes) == graphemes
      """

      result = fix(code)
      refute result =~ "String.graphemes"
      assert result =~ "String.reverse"
      refute result =~ "Enum.reverse"
    end

    test "does not modify unrelated code" do
      code = """
      list = [1, 2, 3]
      list == Enum.reverse(list)
      """

      result = fix(code)
      assert result =~ "Enum.reverse"
      refute result =~ "String.reverse"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def palindrome?(s) do
          cleaned = s |> String.downcase() |> String.graphemes()
          cleaned == Enum.reverse(cleaned)
        end
      end
      """

      result = fix(code)
      assert result =~ "String.downcase"
      assert result =~ "String.reverse"
      assert result =~ "def palindrome?"
      refute result =~ "String.graphemes"
    end

    test "does not auto-fix when graphemes is not terminal in pipe" do
      code = """
      defmodule M do
        def palindrome?(s) do
          cleaned =
            s
            |> String.downcase()
            |> String.graphemes()
            |> Enum.filter(fn c -> c in ?a..?z end)

          cleaned == Enum.reverse(cleaned)
        end
      end
      """

      result = fix(code)
      # Code should remain unchanged — no auto-fix for non-terminal graphemes
      assert result =~ "String.graphemes"
      assert result =~ "Enum.filter"
      assert result =~ "Enum.reverse"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      defmodule M do
        def palindrome?(s) do
          graphemes = String.graphemes(s)
          graphemes == Enum.reverse(graphemes)
        end
      end
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoGraphemePalindromeCheck.check(ast, []) == []
    end

    test "does not strip graphemes when variable is used elsewhere" do
      code = """
      defmodule M do
        def check(s) do
          graphemes = String.graphemes(s)

          if not Enum.all?(graphemes, &only_alpha?/1) or
               not (graphemes == Enum.reverse(graphemes)) do
            false
          else
            true
          end
        end
      end
      """

      result = fix(code)
      assert result =~ "String.graphemes"
    end
  end
end
