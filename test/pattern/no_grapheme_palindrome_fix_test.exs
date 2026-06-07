defmodule Credence.Pattern.NoGraphemePalindromeFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoGraphemePalindrome

  describe "fix — bare variable, used only in the comparison (inline + drop binding)" do
    test "inlines the original string and drops the binding" do
      code = """
      graphemes = String.graphemes(s)
      graphemes == Enum.reverse(graphemes)
      """

      expected = """
      s == String.reverse(s)
      """

      assert fix(NoGraphemePalindrome, code) == expected
    end

    test "handles reversed comparison order" do
      code = """
      graphemes = String.graphemes(s)
      Enum.reverse(graphemes) == graphemes
      """

      expected = """
      String.reverse(s) == s
      """

      assert fix(NoGraphemePalindrome, code) == expected
    end

    test "drops the binding inside a function body and preserves surrounding code" do
      code = """
      defmodule M do
        def palindrome?(s) do
          graphemes = String.graphemes(s)
          graphemes == Enum.reverse(graphemes)
        end
      end
      """

      expected = """
      defmodule M do
        def palindrome?(s) do
          s == String.reverse(s)
        end
      end
      """

      assert fix(NoGraphemePalindrome, code) == expected
    end
  end

  describe "fix — bare variable, still used elsewhere (inline comparison, keep binding)" do
    test "keeps the String.graphemes binding so other list uses are unaffected" do
      code = """
      graphemes = String.graphemes(s)
      pal = graphemes == Enum.reverse(graphemes)
      count = Enum.count(graphemes)
      {pal, count}
      """

      expected = """
      graphemes = String.graphemes(s)
      pal = s == String.reverse(s)
      count = Enum.count(graphemes)
      {pal, count}
      """

      assert fix(NoGraphemePalindrome, code) == expected
    end
  end

  describe "fix — built from a larger expression (strip terminal graphemes, keep var)" do
    test "strips the terminal String.graphemes from a pipe and keeps the variable" do
      code = """
      normalized = s |> String.downcase() |> String.graphemes()
      normalized == Enum.reverse(normalized)
      """

      expected = """
      normalized = s |> String.downcase()
      normalized == String.reverse(normalized)
      """

      assert fix(NoGraphemePalindrome, code) == expected
    end
  end

  describe "fix — leaves unsafe / unrelated code untouched" do
    test "does not fix a pipe-built variable that is used elsewhere" do
      code = """
      normalized = s |> String.downcase() |> String.graphemes()
      pal = normalized == Enum.reverse(normalized)
      count = Enum.count(normalized)
      {pal, count}
      """

      assert fix(NoGraphemePalindrome, code) == code
    end

    test "does NOT rewrite the String.to_charlist form" do
      code = """
      chars = String.to_charlist(s)
      chars == Enum.reverse(chars)
      """

      assert fix(NoGraphemePalindrome, code) == code
    end

    test "does not modify unrelated list comparisons" do
      code = """
      list = [1, 2, 3]
      list == Enum.reverse(list)
      """

      assert fix(NoGraphemePalindrome, code) == code
    end
  end

  describe "round-trip" do
    test "fixed code produces no issues" do
      code = """
      defmodule M do
        def palindrome?(s) do
          graphemes = String.graphemes(s)
          graphemes == Enum.reverse(graphemes)
        end
      end
      """

      assert clean?(NoGraphemePalindrome, fix(NoGraphemePalindrome, code))
    end
  end
end
