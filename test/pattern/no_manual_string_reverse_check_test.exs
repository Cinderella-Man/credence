defmodule Credence.Pattern.NoManualStringReverseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoManualStringReverse

  describe "NoManualStringReverse - check" do
    # --- POSITIVE CASES (should flag) ---

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

      issues = check(NoManualStringReverse, code)
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

      issues = check(NoManualStringReverse, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_string_reverse
    end

    test "detects pipeline with preceding steps" do
      code = """
      defmodule Example do
        def reverse(str) do
          str
          |> String.trim()
          |> String.graphemes()
          |> Enum.reverse()
          |> Enum.join()
        end
      end
      """

      assert length(check(NoManualStringReverse, code)) == 1
    end

    test "detects direct graphemes call piped into reverse and join" do
      code = """
      defmodule Example do
        def reverse(str), do: String.graphemes(str) |> Enum.reverse() |> Enum.join()
      end
      """

      assert length(check(NoManualStringReverse, code)) == 1
    end

    test "detects multiple occurrences in the same module" do
      code = """
      defmodule Example do
        def reverse_both(a, b) do
          r1 = a |> String.graphemes() |> Enum.reverse() |> Enum.join()
          r2 = Enum.join(Enum.reverse(String.graphemes(b)))
          {r1, r2}
        end
      end
      """

      assert length(check(NoManualStringReverse, code)) == 2
    end

    test "detects inside Enum.map" do
      code = """
      Enum.map(list, fn x ->
        x |> String.graphemes() |> Enum.reverse() |> Enum.join()
      end)
      """

      assert length(check(NoManualStringReverse, code)) == 1
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "passes code that uses String.reverse/1" do
      code = """
      defmodule GoodPalindrome do
        def is_palindrome(s) do
          cleaned = String.downcase(s)
          cleaned == String.reverse(cleaned)
        end
      end
      """

      assert check(NoManualStringReverse, code) == []
    end

    test "ignores Enum.reverse used on non-grapheme lists" do
      code = """
      defmodule SafeReverse do
        def process(list) do
          list |> Enum.reverse() |> Enum.join()
        end
      end
      """

      assert check(NoManualStringReverse, code) == []
    end

    test "ignores String.graphemes used without reverse+join" do
      code = """
      defmodule SafeGraphemes do
        def count_chars(s) do
          s |> String.graphemes() |> length()
        end
      end
      """

      assert check(NoManualStringReverse, code) == []
    end

    test "ignores when there is an intermediate step between reverse and join" do
      code = """
      defmodule Example do
        def reverse(str) do
          str
          |> String.graphemes()
          |> Enum.reverse()
          |> Enum.map(& &1)
          |> Enum.join()
        end
      end
      """

      assert check(NoManualStringReverse, code) == []
    end
  end

  describe "graphemes + IO.iodata_to_binary reassemble (always-safe, no promise)" do
    test "detects graphemes |> reverse |> IO.iodata_to_binary pipeline" do
      code =
        ~s[def reverse(str), do: str |> String.graphemes() |> Enum.reverse() |> IO.iodata_to_binary()]

      assert [%Issue{rule: :no_manual_string_reverse}] = check(NoManualStringReverse, code)
    end

    test "detects nested IO.iodata_to_binary(Enum.reverse(String.graphemes(...)))" do
      code = ~s[def reverse(str), do: IO.iodata_to_binary(Enum.reverse(String.graphemes(str)))]
      assert [%Issue{rule: :no_manual_string_reverse}] = check(NoManualStringReverse, code)
    end

    test "does NOT touch codepoints (handled by NoCodepointStringReverse)" do
      code = ~s[def reverse(str), do: str |> String.codepoints() |> Enum.reverse() |> Enum.join()]
      assert check(NoManualStringReverse, code) == []
    end
  end
end
