defmodule Credence.Pattern.NoIntegerToStringDigitsTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoIntegerToStringDigits.check(ast, [])
  end

  defp fix(code), do: Credence.Pattern.NoIntegerToStringDigits.fix(code, [])

  describe "fixable?" do
    test "reports as fixable" do
      assert Credence.Pattern.NoIntegerToStringDigits.fixable?() == true
    end
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

  describe "fix" do
    test "replaces nested form with Integer.digits" do
      code = """
      String.to_charlist(Integer.to_string(number, 2))
      """

      result = fix(code)
      assert result =~ "Integer.digits(number, 2)"
      refute result =~ "String.to_charlist"
      refute result =~ "Integer.to_string"
    end

    test "replaces piped 2-step form with Integer.digits" do
      code = """
      Integer.to_string(number, 2) |> String.to_charlist()
      """

      result = fix(code)
      assert result =~ "Integer.digits(number, 2)"
      refute result =~ "|>"
    end

    test "replaces piped 3-step form with Integer.digits" do
      code = """
      number |> Integer.to_string(2) |> String.to_charlist()
      """

      result = fix(code)
      assert result =~ "Integer.digits(number, 2)"
      refute result =~ "|>"
    end

    test "replaces single-arg Integer.to_string (base 10)" do
      code = """
      String.to_charlist(Integer.to_string(number))
      """

      result = fix(code)
      assert result =~ "Integer.digits(number)"
      refute result =~ "String.to_charlist"
    end

    test "does not modify unrelated code" do
      code = """
      Integer.to_string(number, 2)
      """

      result = fix(code)
      assert result =~ "Integer.to_string"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def bits(n) do
          digits = String.to_charlist(Integer.to_string(n, 2))
          length(digits)
        end
      end
      """

      result = fix(code)
      assert result =~ "Integer.digits(n, 2)"
      assert result =~ "length(digits)"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      String.to_charlist(Integer.to_string(number, 2))
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoIntegerToStringDigits.check(ast, []) == []
    end
  end
end
