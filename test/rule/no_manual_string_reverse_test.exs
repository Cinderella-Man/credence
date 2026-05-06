defmodule Credence.Pattern.NoManualStringReverseTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoManualStringReverse.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoManualStringReverse.fix(code, [])
  end

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

      assert length(check(code)) == 1
    end

    test "detects direct graphemes call piped into reverse and join" do
      code = """
      defmodule Example do
        def reverse(str), do: String.graphemes(str) |> Enum.reverse() |> Enum.join()
      end
      """

      assert length(check(code)) == 1
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

      assert length(check(code)) == 2
    end

    test "detects inside Enum.map" do
      code = """
      Enum.map(list, fn x ->
        x |> String.graphemes() |> Enum.reverse() |> Enum.join()
      end)
      """

      assert length(check(code)) == 1
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

      assert check(code) == []
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

      assert check(code) == []
    end
  end

  describe "NoManualStringReverse - fix" do
    test "fixes simple pipeline" do
      code = ~S'''
      defmodule Example do
        def reverse(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join()
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.reverse(str)"
      refute fixed =~ "String.graphemes"
      refute fixed =~ "Enum.reverse"
      refute fixed =~ "Enum.join"
    end

    test "fixes nested call form" do
      code = ~S'''
      defmodule Example do
        def reverse(str), do: Enum.join(Enum.reverse(String.graphemes(str)))
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.reverse(str)"
      refute fixed =~ "String.graphemes"
      refute fixed =~ "Enum.reverse"
      refute fixed =~ "Enum.join"
    end

    test "fixes pipeline with preceding steps" do
      code = ~S'''
      defmodule Example do
        def reverse(str) do
          str
          |> String.trim()
          |> String.graphemes()
          |> Enum.reverse()
          |> Enum.join()
        end
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.trim()"
      assert fixed =~ "String.reverse()"
      refute fixed =~ "String.graphemes"
      refute fixed =~ "Enum.reverse"
      refute fixed =~ "Enum.join"
    end

    test "fixes direct graphemes call in pipeline" do
      code = ~S'''
      defmodule Example do
        def reverse(str), do: String.graphemes(str) |> Enum.reverse() |> Enum.join()
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.reverse(str)"
      refute fixed =~ "String.graphemes"
      refute fixed =~ "Enum.reverse"
      refute fixed =~ "Enum.join"
    end

    test "fixes multiple occurrences" do
      code = ~S'''
      defmodule Example do
        def reverse_both(a, b) do
          r1 = a |> String.graphemes() |> Enum.reverse() |> Enum.join()
          r2 = Enum.join(Enum.reverse(String.graphemes(b)))
          {r1, r2}
        end
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.reverse(a)"
      assert fixed =~ "String.reverse(b)"
      refute fixed =~ "String.graphemes"
    end

    test "preserves pipeline steps after Enum.join" do
      code = ~S'''
      defmodule Example do
        def reverse(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join() |> String.trim()
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.reverse(str)"
      assert fixed =~ "String.trim()"
      refute fixed =~ "String.graphemes"
      refute fixed =~ "Enum.reverse"
      refute fixed =~ "Enum.join"
    end

    test "preserves pipeline steps before graphemes" do
      code = ~S'''
      defmodule Example do
        def reverse(str) do
          str
          |> String.downcase()
          |> String.trim()
          |> String.graphemes()
          |> Enum.reverse()
          |> Enum.join()
        end
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.downcase()"
      assert fixed =~ "String.trim()"
      assert fixed =~ "String.reverse()"
      refute fixed =~ "String.graphemes"
      refute fixed =~ "Enum.reverse"
      refute fixed =~ "Enum.join"
    end

    test "fixes inside fn body" do
      code = ~S'''
      Enum.map(list, fn x ->
        x |> String.graphemes() |> Enum.reverse() |> Enum.join()
      end)
      '''

      fixed = fix(code)
      assert fixed =~ "String.reverse(x)"
      refute fixed =~ "String.graphemes"
      refute fixed =~ "Enum.reverse"
      refute fixed =~ "Enum.join"
    end

    test "does not modify code already using String.reverse/1" do
      code = ~S'''
      defmodule GoodPalindrome do
        def is_palindrome(s) do
          cleaned = String.downcase(s)
          cleaned == String.reverse(cleaned)
        end
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.downcase"
      assert fixed =~ "String.reverse(cleaned)"
    end

    test "does not modify Enum.join with separator" do
      code = ~S'''
      defmodule Example do
        def reverse(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join("-")
      end
      '''

      fixed = fix(code)
      assert fixed =~ "String.graphemes"
      assert fixed =~ "Enum.reverse"
      assert fixed =~ "Enum.join"
    end

    test "does not modify unrelated pipelines" do
      code = ~S'''
      defmodule Example do
        def process(list), do: list |> Enum.reverse() |> Enum.join()
      end
      '''

      fixed = fix(code)
      assert fixed =~ "Enum.reverse"
      assert fixed =~ "Enum.join"
    end
  end
end
