defmodule Credence.Pattern.NoIntegerToStringContainsTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoIntegerToStringContains

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoIntegerToStringContains.check(ast, [])
  end

  describe "detection" do
    test "passes code that uses Integer.digits with Enum.any?" do
      code = """
      defmodule GoodDigits do
        def has_lucky_digit?(n) do
          n
          |> Integer.digits()
          |> Enum.any?(&(&1 in [4, 7]))
        end
      end
      """

      assert check(code) == []
    end

    test "passes String.contains? on non-Integer.to_string input" do
      code = """
      defmodule SafeContains do
        def has_four?(s) do
          String.contains?(s, "4")
        end
      end
      """

      assert check(code) == []
    end

    test "passes Integer.to_string used without String.contains?" do
      code = """
      defmodule SafeToString do
        def as_string(n) do
          Integer.to_string(n)
        end
      end
      """

      assert check(code) == []
    end

    test "detects nested String.contains?(Integer.to_string(n), [\"4\", \"7\"])" do
      code = """
      defmodule BadNested do
        def has_lucky?(n) do
          String.contains?(Integer.to_string(n), ["4", "7"])
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_integer_to_string_contains
      assert issue.message =~ "Integer.digits/1"
      assert issue.meta.line != nil
    end

    test "detects piped 2-step form" do
      code = """
      defmodule BadPiped do
        def has_lucky?(n) do
          Integer.to_string(n) |> String.contains?(["4", "7"])
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_integer_to_string_contains
    end

    test "detects piped 3-step form" do
      code = """
      defmodule BadFullPipe do
        def has_lucky?(n) do
          n |> Integer.to_string() |> String.contains?(["4", "7"])
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_integer_to_string_contains
    end

    test "detects single-digit check" do
      code = """
      defmodule BadSingleDigit do
        def has_four?(n) do
          n |> Integer.to_string() |> String.contains?(["4"])
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_integer_to_string_contains
    end

    test "ignores String.contains? with multi-character strings" do
      code = """
      defmodule SafeMultiChar do
        def has_sequence?(n) do
          n |> Integer.to_string() |> String.contains?(["47", "74"])
        end
      end
      """

      assert check(code) == []
    end

    test "ignores String.contains? with mixed-length strings" do
      code = """
      defmodule SafeMixed do
        def check?(n) do
          n |> Integer.to_string() |> String.contains?(["4", "77"])
        end
      end
      """

      assert check(code) == []
    end

    test "ignores non-list second argument to String.contains?" do
      code = """
      defmodule SafeNonList do
        def has_four?(n) do
          n |> Integer.to_string() |> String.contains?("4")
        end
      end
      """

      assert check(code) == []
    end

    test "reports line number" do
      code = """
      defmodule LineCheck do
        def has_lucky?(n) do
          n |> Integer.to_string() |> String.contains?(["4", "7"])
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).meta.line != nil
    end
  end

  describe "fix" do
    test "returns empty patches (check-only rule)" do
      code = """
      n |> Integer.to_string() |> String.contains?(["4", "7"])
      """

      ast = Sourceror.parse_string!(code)
      assert NoIntegerToStringContains.fix_patches(ast, []) == []
    end
  end
end
