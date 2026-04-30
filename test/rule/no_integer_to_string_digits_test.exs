defmodule Credence.Rule.NoIntegerToStringDigitsTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoIntegerToStringDigits.check(ast, [])
  end

  describe "NoIntegerToStringDigits" do
    test "passes code that uses Integer.digits/2" do
      code = """
      defmodule GoodDigits do
        def binary_digits(n) do
          Integer.digits(n, 2)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Integer.to_string used without to_charlist" do
      code = """
      defmodule SafeToString do
        def as_binary_string(n) do
          Integer.to_string(n, 2)
        end
      end
      """

      assert check(code) == []
    end

    test "detects nested String.to_charlist(Integer.to_string(n, base))" do
      code = """
      defmodule BadNested do
        def binary_bits(n) do
          String.to_charlist(Integer.to_string(n, 2))
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_integer_to_string_digits
      assert issue.severity == :warning
      assert issue.message =~ "Integer.digits/2"
      assert issue.meta.line != nil
    end

    test "detects piped Integer.to_string(n, base) |> String.to_charlist()" do
      code = """
      defmodule BadPiped do
        def binary_bits(n) do
          Integer.to_string(n, 2) |> String.to_charlist()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_integer_to_string_digits
    end

    test "detects fully piped n |> Integer.to_string(base) |> String.to_charlist()" do
      code = """
      defmodule BadFullPipe do
        def binary_bits(n) do
          n |> Integer.to_string(2) |> String.to_charlist()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_integer_to_string_digits
    end

    test "ignores String.to_charlist on non-Integer.to_string input" do
      code = """
      defmodule SafeCharlist do
        def to_chars(s) do
          String.to_charlist(s)
        end
      end
      """

      assert check(code) == []
    end
  end
end
