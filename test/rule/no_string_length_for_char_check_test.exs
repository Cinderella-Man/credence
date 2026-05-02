defmodule Credence.Rule.NoStringLengthForCharCheckTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoStringLengthForCharCheck.check(ast, [])
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
end
