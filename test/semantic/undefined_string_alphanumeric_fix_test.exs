defmodule Credence.Semantic.UndefinedStringAlphanumericFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.UndefinedStringAlphanumeric

  defp diag(line, col \\ 1) do
    %{
      severity: :warning,
      message: "String.alphanumeric?/1 is undefined or private",
      position: {line, col}
    }
  end

  describe "fix/2 — capture form (&String.alphanumeric?/1)" do
    test "replaces in Enum.filter pipeline" do
      source = """
      defmodule M do
        def clean(s) do
          s
          |> String.downcase()
          |> String.graphemes()
          |> Enum.filter(&String.alphanumeric?/1)
        end
      end
      """

      expected = """
      defmodule M do
        def clean(s) do
          s
          |> String.downcase()
          |> String.graphemes()
          |> Enum.filter(fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end)
        end
      end
      """

      assert UndefinedStringAlphanumeric.fix(source, diag(6)) == expected
    end

    test "replaces exact palindrome pattern from pipeline log" do
      source = """
      defmodule PalindromeChecker do
        def palindrome?(input_string) when is_binary(input_string) do
          cleaned = input_string
            |> String.downcase()
            |> String.graphemes()
            |> Enum.filter(&String.alphanumeric?/1)

          cleaned == Enum.reverse(cleaned)
        end
      end
      """

      expected = """
      defmodule PalindromeChecker do
        def palindrome?(input_string) when is_binary(input_string) do
          cleaned = input_string
            |> String.downcase()
            |> String.graphemes()
            |> Enum.filter(fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end)

          cleaned == Enum.reverse(cleaned)
        end
      end
      """

      assert UndefinedStringAlphanumeric.fix(source, diag(6)) == expected
    end

    test "replaces in Enum.reject" do
      source = """
      defmodule M do
        def strip(s), do: String.graphemes(s) |> Enum.reject(&String.alphanumeric?/1)
      end
      """

      expected = """
      defmodule M do
        def strip(s), do: String.graphemes(s) |> Enum.reject(fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end)
      end
      """

      assert UndefinedStringAlphanumeric.fix(source, diag(2)) == expected
    end
  end

  describe "fix/2 — direct call form (String.alphanumeric?(expr))" do
    test "replaces direct call with variable" do
      source = """
      defmodule M do
        def alnum?(c), do: String.alphanumeric?(c)
      end
      """

      expected = """
      defmodule M do
        def alnum?(c), do: String.match?(c, ~r/^[a-zA-Z0-9]$/)
      end
      """

      assert UndefinedStringAlphanumeric.fix(source, diag(2)) == expected
    end

    test "replaces direct call inside if" do
      source = """
      defmodule M do
        def check(char) do
          if String.alphanumeric?(char), do: :yes, else: :no
        end
      end
      """

      expected = """
      defmodule M do
        def check(char) do
          if String.match?(char, ~r/^[a-zA-Z0-9]$/), do: :yes, else: :no
        end
      end
      """

      assert UndefinedStringAlphanumeric.fix(source, diag(3)) == expected
    end
  end

  describe "fix/2 — does not touch other lines" do
    test "only modifies the flagged line" do
      source = """
      defmodule M do
        def a(s), do: String.graphemes(s) |> Enum.filter(&String.alphanumeric?/1)
        def b(s), do: String.graphemes(s) |> Enum.filter(&String.alphanumeric?/1)
      end
      """

      # Only line 2 (def a) is rewritten; line 3 (def b) keeps the capture form.
      expected = """
      defmodule M do
        def a(s), do: String.graphemes(s) |> Enum.filter(fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end)
        def b(s), do: String.graphemes(s) |> Enum.filter(&String.alphanumeric?/1)
      end
      """

      assert UndefinedStringAlphanumeric.fix(source, diag(2)) == expected
    end
  end

  describe "fix/2 — no-ops" do
    test "returns source unchanged when position is nil" do
      source = """
      some code
      """

      bad_diag = %{
        severity: :warning,
        message: "String.alphanumeric?/1 is undefined or private",
        position: nil
      }

      assert UndefinedStringAlphanumeric.fix(source, bad_diag) == source
    end

    test "returns source unchanged when line has no match" do
      source = """
      defmodule M do
        def foo, do: :ok
      end
      """

      assert UndefinedStringAlphanumeric.fix(source, diag(2)) == source
    end
  end

  describe "integration through Credence.Semantic" do
    test "fixes String.alphanumeric? end-to-end" do
      source = """
      defmodule AlphanumFixInteg1 do
        def clean(s) do
          s |> String.graphemes() |> Enum.filter(&String.alphanumeric?/1)
        end
      end
      """

      expected = """
      defmodule AlphanumFixInteg1 do
        def clean(s) do
          s |> String.graphemes() |> Enum.filter(fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end)
        end
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed == expected
    end

    test "does not modify code that already uses String.match?" do
      source = """
      defmodule AlphanumFixInteg2 do
        def clean(s) do
          s
          |> String.graphemes()
          |> Enum.filter(fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end)
        end
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed == source
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      source = """
      defmodule M do
        def clean(s) do
          s
          |> String.graphemes()
          |> Enum.filter(&String.alphanumeric?/1)
        end
      end
      """

      assert valid_syntax?(UndefinedStringAlphanumeric.fix(source, diag(5)))
    end
  end
end
