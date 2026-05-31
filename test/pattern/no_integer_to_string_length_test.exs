defmodule Credence.Pattern.NoIntegerToStringLengthTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoIntegerToStringLength

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoIntegerToStringLength.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoIntegerToStringLength, code, [])

  describe "NoIntegerToStringLength" do
    test "passes code that uses Integer.digits/2 |> length()" do
      code = """
      defmodule GoodDigits do
        def bit_length(n) do
          Integer.digits(n, 2) |> length()
        end
      end
      """

      assert check(code) == []
    end

    test "passes Integer.to_string used without String.length" do
      code = """
      defmodule SafeToString do
        def as_binary_string(n) do
          Integer.to_string(n, 2)
        end
      end
      """

      assert check(code) == []
    end

    test "passes String.length on non-Integer.to_string input" do
      code = """
      defmodule SafeLength do
        def str_len(s) do
          String.length(s)
        end
      end
      """

      assert check(code) == []
    end

    test "detects nested String.length(Integer.to_string(n, base))" do
      code = """
      defmodule BadNested do
        def bit_length(n) do
          String.length(Integer.to_string(n, 2))
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_integer_to_string_length

      assert issue.message =~ "Integer.digits/2"
      assert issue.meta.line != nil
    end

    test "detects piped Integer.to_string(n, base) |> String.length()" do
      code = """
      defmodule BadPiped do
        def bit_length(n) do
          Integer.to_string(n, 2) |> String.length()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_integer_to_string_length
    end

    test "detects fully piped n |> Integer.to_string(base) |> String.length()" do
      code = """
      defmodule BadFullPipe do
        def bit_length(n) do
          n |> Integer.to_string(2) |> String.length()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_integer_to_string_length
    end
  end

  describe "fix" do
    test "replaces nested form with Integer.digits |> length" do
      code = """
      String.length(Integer.to_string(number, 2))
      """

      result = fix(code)
      assert result =~ "Integer.digits(number, 2)"
      assert result =~ "length("
      refute result =~ "String.length"
      refute result =~ "Integer.to_string"
    end

    test "replaces piped 2-step form with Integer.digits |> length" do
      code = """
      Integer.to_string(number, 2) |> String.length()
      """

      result = fix(code)
      assert result =~ "Integer.digits(number, 2)"
      assert result =~ "length()"
      refute result =~ "String.length"
    end

    test "replaces piped 3-step form with Integer.digits |> length" do
      code = """
      number |> Integer.to_string(2) |> String.length()
      """

      result = fix(code)
      assert result =~ "Integer.digits(number, 2)"
      assert result =~ "length()"
      refute result =~ "String.length"
    end

    test "replaces single-arg Integer.to_string (base 10)" do
      code = """
      String.length(Integer.to_string(number))
      """

      result = fix(code)
      assert result =~ "Integer.digits(number)"
      assert result =~ "length("
      refute result =~ "String.length"
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
          len = String.length(Integer.to_string(n, 2))
          len + 1
        end
      end
      """

      result = fix(code)
      assert result =~ "Integer.digits(n, 2)"
      assert result =~ "len + 1"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      String.length(Integer.to_string(number, 2))
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoIntegerToStringLength.check(ast, []) == []
    end
  end
end
