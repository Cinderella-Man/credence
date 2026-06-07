defmodule Credence.Semantic.UndefinedStringAlphanumericCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedStringAlphanumeric

  describe "match?/1" do
    test "matches String.alphanumeric? undefined warning" do
      diag = %{
        severity: :warning,
        message: "String.alphanumeric?/1 is undefined or private",
        position: {11, 30}
      }

      assert UndefinedStringAlphanumeric.match?(diag)
    end

    test "matches warning with surrounding context" do
      diag = %{
        severity: :warning,
        message:
          "String.alphanumeric?/1 is undefined or private. " <>
            "Did you mean: String.printable?/1",
        position: {11, 30}
      }

      assert UndefinedStringAlphanumeric.match?(diag)
    end

    test "does not match error severity" do
      diag = %{
        severity: :error,
        message: "String.alphanumeric?/1 is undefined or private",
        position: {11, 30}
      }

      refute UndefinedStringAlphanumeric.match?(diag)
    end

    test "does not match other undefined function warnings" do
      diag = %{
        severity: :warning,
        message: "MyModule.foo/1 is undefined or private",
        position: {5, 1}
      }

      refute UndefinedStringAlphanumeric.match?(diag)
    end

    test "does not match unrelated warning" do
      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: {5, 6}
      }

      refute UndefinedStringAlphanumeric.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{
        severity: :warning,
        message: "String.alphanumeric?/1 is undefined or private",
        position: {11, 30}
      }

      issue = UndefinedStringAlphanumeric.to_issue(diag)
      assert issue.rule == :undefined_string_alphanumeric
      assert issue.meta.line == 11
    end

    test "handles bare integer position" do
      diag = %{
        severity: :warning,
        message: "String.alphanumeric?/1 is undefined or private",
        position: 11
      }

      issue = UndefinedStringAlphanumeric.to_issue(diag)
      assert issue.meta.line == 11
    end
  end

  describe "integration through Credence.Semantic" do
    test "detects String.alphanumeric? in module" do
      source = """
      defmodule AlphanumCheckInteg1 do
        def clean(s) do
          s |> String.graphemes() |> Enum.filter(&String.alphanumeric?/1)
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :undefined_string_alphanumeric))
      refute Enum.empty?(matched)
    end

    test "no issues when String.match? is used correctly" do
      source = """
      defmodule AlphanumCheckInteg2 do
        def clean(s) do
          s
          |> String.graphemes()
          |> Enum.filter(fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end)
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :undefined_string_alphanumeric))
      assert matched == []
    end
  end
end
