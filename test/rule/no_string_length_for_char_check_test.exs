defmodule Credence.Rule.NoStringLengthForCharCheckTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoStringLengthForCharCheck.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoStringLengthForCharCheck.fix(code, [])
  end

  describe "NoStringLengthForCharCheck" do
    test "passes code that uses pattern matching for single char" do
      code = """
      defmodule GoodCheck do
        def count_char(string, <<_::utf8>> = target) do
          String.graphemes(string) |> Enum.count(&(&1 == target))
        end
      end
      """

      assert check(code) == []
    end

    test "detects String.length(x) != 1" do
      code = """
      defmodule BadCheck do
        def count_char(string, target_char) do
          if String.length(target_char) != 1 do
            raise ArgumentError, "target must be a single character"
          end
          String.graphemes(string) |> Enum.count(&(&1 == target_char))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_string_length_for_char_check
      assert issue.message =~ "String.length/1"
      assert issue.meta.line != nil
    end

    test "detects String.length(x) == 1" do
      code = """
      defmodule BadEq do
        def single_char?(s) do
          String.length(s) == 1
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_string_length_for_char_check
    end

    test "detects reversed form: 1 == String.length(x)" do
      code = """
      defmodule BadReversed do
        def single_char?(s) do
          1 == String.length(s)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "ignores String.length compared to other numbers" do
      code = """
      defmodule SafeLength do
        def long_enough?(s) do
          String.length(s) >= 8
        end
      end
      """

      assert check(code) == []
    end

    test "ignores length/1 (not String.length)" do
      code = """
      defmodule SafeListLength do
        def single?(list) do
          length(list) == 1
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix: String.length(x) == 1" do
    test "replaces == with match?" do
      input = """
      defmodule Example do
        def single_char?(s) do
          String.length(s) == 1
        end
      end
      """

      result = fix(input)
      assert result =~ "match?([_], String.graphemes(s))"
      refute result =~ "String.length"
    end

    test "replaces reversed form 1 == String.length(x)" do
      input = """
      defmodule Example do
        def single_char?(s) do
          1 == String.length(s)
        end
      end
      """

      result = fix(input)
      assert result =~ "match?([_], String.graphemes(s))"
      refute result =~ "String.length"
    end

    test "replaces != with not match?" do
      input = """
      defmodule Example do
        def validate!(s) do
          if String.length(s) != 1 do
            raise ArgumentError, "expected a single character"
          end
        end
      end
      """

      result = fix(input)
      assert result =~ "not match?([_], String.graphemes(s))"
      refute result =~ "String.length"
    end

    test "replaces reversed form 1 != String.length(x)" do
      input = """
      defmodule Example do
        def validate!(s) do
          if 1 != String.length(s) do
            raise ArgumentError, "expected a single character"
          end
        end
      end
      """

      result = fix(input)
      assert result =~ "not match?([_], String.graphemes(s))"
      refute result =~ "String.length"
    end

    test "replaces === the same as ==" do
      input = """
      defmodule Example do
        def single_char?(s) do
          String.length(s) === 1
        end
      end
      """

      result = fix(input)
      assert result =~ "match?([_], String.graphemes(s))"
      refute result =~ "String.length"
    end

    test "replaces !== the same as !=" do
      input = """
      defmodule Example do
        def validate!(s) do
          if String.length(s) !== 1 do
            raise ArgumentError, "bad"
          end
        end
      end
      """

      result = fix(input)
      assert result =~ "not match?([_], String.graphemes(s))"
      refute result =~ "String.length"
    end

    test "does not alter String.length compared to other numbers" do
      code = """
      defmodule Example do
        def long_enough?(s) do
          String.length(s) >= 8
        end
      end
      """

      result = fix(code)
      assert result =~ "String.length(s) >= 8"
    end

    test "does not alter plain length/1 == 1" do
      code = """
      defmodule Example do
        def single?(list) do
          length(list) == 1
        end
      end
      """

      result = fix(code)
      assert result =~ "length(list) == 1"
    end

    test "fixes multiple occurrences in the same module" do
      input = """
      defmodule Example do
        def validate(s) do
          if String.length(s) != 1 do
            raise "bad"
          end
          String.length(s) == 1
        end
      end
      """

      result = fix(input)
      assert result =~ "not match?([_], String.graphemes(s))"
      assert result =~ "match?([_], String.graphemes(s))"
      refute result =~ "String.length"
    end

    test "preserves surrounding code" do
      input = """
      defmodule Example do
        @doc "checks char"
        def single_char?(s) do
          x = String.upcase(s)
          String.length(x) == 1
        end
      end
      """

      result = fix(input)
      assert result =~ "@doc"
      assert result =~ "String.upcase(s)"
      assert result =~ "match?([_], String.graphemes(x))"
    end
  end
end
