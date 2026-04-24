defmodule Credence.Rule.NoManualStringReverseTest do
  use ExUnit.Case
  alias Credence.Issue

  describe "analyze/2 - NoManualStringReverse Rule" do
    test "passes code that uses String.reverse/1" do
      code = """
      defmodule GoodPalindrome do
        def is_palindrome(s) do
          cleaned = String.downcase(s)
          cleaned == String.reverse(cleaned)
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
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

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert %Issue{} = issue
      assert issue.rule == :no_manual_string_reverse
      assert issue.severity == :warning
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

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert issue.rule == :no_manual_string_reverse
    end

    test "ignores Enum.reverse used on non-grapheme lists" do
      code = """
      defmodule SafeReverse do
        def process(list) do
          list |> Enum.reverse() |> Enum.join()
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end

    test "ignores String.graphemes used without reverse+join" do
      code = """
      defmodule SafeGraphemes do
        def count_chars(s) do
          s |> String.graphemes() |> length()
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end
  end
end
