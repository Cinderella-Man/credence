defmodule Credence.Rule.NoManualStringReverseTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoManualStringReverse.check(ast, [])
  end

  describe "NoManualStringReverse" do
    test "passes code that uses String.reverse/1" do
      code = """
      defmodule GoodPalindrome do
        def is_palindrome(s) do
          cleaned = String.downcase(s)
          cleaned == String.reverse(cleaned)
        end
      end
      """

      assert check(code) == []
    end

    test "detects String.graphemes |> Enum.reverse |> Enum.join pipeline" do
      code = """
      defmodule BadPalindrome do
        def is_palindrome(word) do
          normalized = String.downcase(word)
          reversed = normalized |> String.graphemes() |> Enum.reverse() |> Enum.join()
          normalized == reversed
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_manual_string_reverse

      assert issue.message =~ "String.reverse/1"
      assert issue.meta.line != nil
    end

    test "detects the nested call form Enum.join(Enum.reverse(String.graphemes(...)))" do
      code = """
      defmodule BadNested do
        def reverse_string(s) do
          Enum.join(Enum.reverse(String.graphemes(s)))
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_string_reverse
    end

    test "ignores Enum.reverse used on non-grapheme lists" do
      code = """
      defmodule SafeReverse do
        def process(list) do
          list |> Enum.reverse() |> Enum.join()
        end
      end
      """

      assert check(code) == []
    end

    test "ignores String.graphemes used without reverse+join" do
      code = """
      defmodule SafeGraphemes do
        def count_chars(s) do
          s |> String.graphemes() |> length()
        end
      end
      """

      assert check(code) == []
    end
  end
end
