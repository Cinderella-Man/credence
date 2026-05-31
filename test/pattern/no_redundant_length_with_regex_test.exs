defmodule Credence.Pattern.NoRedundantLengthWithRegexTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantLengthWithRegex
  alias Credence.Issue

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRedundantLengthWithRegex.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoRedundantLengthWithRegex, code, [])
  end

  describe "check" do
    test "detects String.length(x) == N and Regex.match? with anchored {N} quantifier" do
      code = """
      defmodule Bad do
        def validate(input) do
          if String.length(input) == 10 and Regex.match?(~r/^\\d{10}$/, input) do
            "valid"
          else
            "invalid"
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_redundant_length_with_regex
      assert issue.message =~ "String.length/1"
      assert issue.message =~ "redundant"
      assert issue.meta.line != nil
    end

    test "detects reversed: Regex.match? and String.length(x) == N" do
      code = """
      defmodule BadReversed do
        def validate(input) do
          if Regex.match?(~r/^\\d{10}$/, input) and String.length(input) == 10 do
            "valid"
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_redundant_length_with_regex
    end

    test "detects String.match? variant" do
      code = """
      defmodule BadStringMatch do
        def validate(input) do
          String.length(input) == 6 and String.match?(input, ~r/^[A-Z]{6}$/)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects === variant" do
      code = """
      defmodule BadStrictEqual do
        def validate(input) do
          String.length(input) === 10 and Regex.match?(~r/^\\d{10}$/, input)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects reversed === variant" do
      code = """
      defmodule BadStrictEqualReversed do
        def validate(input) do
          10 === String.length(input) and Regex.match?(~r/^\\d{10}$/, input)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "ignores length check without regex match" do
      code = """
      defmodule Good do
        def validate(input) do
          String.length(input) == 10
        end
      end
      """

      assert check(code) == []
    end

    test "ignores regex match without length check" do
      code = """
      defmodule Good do
        def validate(input) do
          Regex.match?(~r/^\\d{10}$/, input)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores when length N does not match regex quantifier" do
      code = """
      defmodule Good do
        def validate(input) do
          String.length(input) == 5 and Regex.match?(~r/^\\d{10}$/, input)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores unanchored regex" do
      code = """
      defmodule Good do
        def validate(input) do
          String.length(input) == 10 and Regex.match?(~r/\\d{10}/, input)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores regex anchored only at start" do
      code = """
      defmodule Good do
        def validate(input) do
          String.length(input) == 10 and Regex.match?(~r/^\\d{10}/, input)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores regex anchored only at end" do
      code = """
      defmodule Good do
        def validate(input) do
          String.length(input) == 10 and Regex.match?(~r/\\d{10}$/, input)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores non-integer length comparison" do
      code = """
      defmodule Good do
        def validate(input, n) do
          String.length(input) == n and Regex.match?(~r/^\\d{10}$/, input)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores length check with > or >= comparison" do
      code = """
      defmodule Good do
        def validate(input) do
          String.length(input) >= 10 and Regex.match?(~r/^\\d{10}$/, input)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores non-String.length (e.g. length/1)" do
      code = """
      defmodule Good do
        def validate(list) do
          length(list) == 10 and Regex.match?(~r/^\\d{10}$/, "hello")
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "removes redundant length check on the left side" do
      input = """
      defmodule Example do
        def validate(input) do
          if String.length(input) == 10 and Regex.match?(~r/^\\d{10}$/, input) do
            "valid"
          end
        end
      end
      """

      result = fix(input)
      assert result =~ "Regex.match?(~r/^\\d{10}$/, input)"
      refute result =~ "String.length"
    end

    test "removes redundant length check on the right side" do
      input = """
      defmodule Example do
        def validate(input) do
          if Regex.match?(~r/^\\d{10}$/, input) and String.length(input) == 10 do
            "valid"
          end
        end
      end
      """

      result = fix(input)
      assert result =~ "Regex.match?(~r/^\\d{10}$/, input)"
      refute result =~ "String.length"
    end

    test "preserves surrounding code" do
      input = """
      defmodule Example do
        @doc "validates phone"
        def validate(input) do
          prefix = String.trim(input)
          if String.length(prefix) == 10 and Regex.match?(~r/^\\d{10}$/, prefix) do
            "valid"
          end
        end
      end
      """

      result = fix(input)
      assert result =~ "@doc"
      assert result =~ "String.trim(input)"
      assert result =~ "Regex.match?(~r/^\\d{10}$/, prefix)"
      refute result =~ "String.length"
    end

    test "handles String.match? variant" do
      input = """
      defmodule Example do
        def validate(code) do
          if String.length(code) == 6 and String.match?(code, ~r/^[A-Z]{6}$/) do
            "ok"
          end
        end
      end
      """

      result = fix(input)
      assert result =~ "String.match?(code, ~r/^[A-Z]{6}$/)"
      refute result =~ "String.length"
    end
  end
end
