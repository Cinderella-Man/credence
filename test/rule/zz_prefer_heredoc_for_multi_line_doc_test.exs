defmodule Credence.Pattern.ZzPreferHeredocForMultiLineDocTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.ZzPreferHeredocForMultiLineDoc.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.ZzPreferHeredocForMultiLineDoc.fix(code, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.ZzPreferHeredocForMultiLineDoc.fixable?() == true
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — positive cases" do
    test "flags @doc with internal newline" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two."
        def foo, do: :ok
      end
      """

      [issue] = check(code)
      assert issue.rule == :prefer_heredoc_for_multi_line_doc
      assert issue.message =~ "heredoc"
    end

    test "flags @doc with multiple internal newlines" do
      code = """
      defmodule Example do
        @doc "Line one.\\n\\nLine two.\\nLine three."
        def foo, do: :ok
      end
      """

      [issue] = check(code)
      assert issue.rule == :prefer_heredoc_for_multi_line_doc
    end

    test "flags @moduledoc with internal newlines" do
      code = """
      defmodule Example do
        @moduledoc "Module for things.\\nDoes stuff."
        def foo, do: :ok
      end
      """

      [issue] = check(code)
      assert issue.message =~ "@moduledoc"
    end

    test "flags @typedoc with internal newlines" do
      code = """
      defmodule Example do
        @typedoc "A custom type.\\nWith details."
        @type t :: atom()
      end
      """

      [issue] = check(code)
      assert issue.message =~ "@typedoc"
    end

    test "flags multi-line @doc with trailing newline" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two.\\n"
        def foo, do: :ok
      end
      """

      [issue] = check(code)
      assert issue.rule == :prefer_heredoc_for_multi_line_doc
    end

    test "flags verbose LLM-style doc with sections" do
      code = """
      defmodule Example do
        @doc "Counts occurrences.\\n\\n## Parameters\\n\\n- string: the input\\n- target: the char\\n"
        def count_char(s, t), do: 0
      end
      """

      [issue] = check(code)
      assert issue.rule == :prefer_heredoc_for_multi_line_doc
    end
  end

  describe "check/2 — negative cases" do
    test "does not flag single-line @doc without newlines" do
      code = """
      defmodule Example do
        @doc "A simple one-liner."
        def foo, do: :ok
      end
      """

      assert check(code) == []
    end

    test "does not flag @doc with only trailing newline (no internal)" do
      code = """
      defmodule Example do
        @doc "Single line.\\n"
        def foo, do: :ok
      end
      """

      # This is for NoTrailingNewlineInDoc, not this rule
      assert check(code) == []
    end

    test "does not flag @doc false" do
      code = """
      defmodule Example do
        @doc false
        def foo, do: :ok
      end
      """

      assert check(code) == []
    end

    test "does not flag non-doc attributes" do
      code = """
      defmodule Example do
        @my_attr "value\\nwith newline"
        def foo, do: :ok
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2" do
    test "converts simple two-line @doc to heredoc" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two."
        def foo, do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@doc """|
      assert fixed =~ "  Line one."
      assert fixed =~ "  Line two."
      assert fixed =~ ~S|  """|
      refute fixed =~ "\\n"
    end

    test "converts @moduledoc to heredoc" do
      code = """
      defmodule Example do
        @moduledoc "Module overview.\\nMore details."
        def foo, do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@moduledoc """|
      assert fixed =~ "  Module overview."
      assert fixed =~ "  More details."
    end

    test "converts @typedoc to heredoc" do
      code = """
      defmodule Example do
        @typedoc "A custom type.\\nWith explanation."
        @type t :: atom()
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@typedoc """|
      assert fixed =~ "  A custom type."
      assert fixed =~ "  With explanation."
    end

    test "strips trailing \\n in conversion" do
      code = """
      defmodule Example do
        @doc "Line one.\\nLine two.\\n"
        def foo, do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@doc """|
      assert fixed =~ "  Line one."
      assert fixed =~ "  Line two."
      # Should not have an extra blank line before closing """
      refute fixed =~ "\\n"
    end

    test "handles blank lines from consecutive \\n" do
      code = """
      defmodule Example do
        @doc "Summary.\\n\\nDetails here."
        def foo, do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@doc """|
      assert fixed =~ "  Summary."
      assert fixed =~ "  Details here."
      # There should be a blank line between summary and details
      lines = String.split(fixed, "\n")
      summary_idx = Enum.find_index(lines, &String.contains?(&1, "Summary."))
      details_idx = Enum.find_index(lines, &String.contains?(&1, "Details here."))
      assert details_idx - summary_idx == 2
    end

    test "preserves indentation level" do
      code = """
      defmodule Outer do
        defmodule Inner do
          @doc "Deep doc.\\nWith detail."
          def bar, do: :ok
        end
      end
      """

      fixed = fix(code)
      lines = String.split(fixed, "\n")
      opening = Enum.find(lines, &String.contains?(&1, ~S|@doc """|))
      assert opening != nil
      # The opening should have 4-space indent (2 per nesting level)
      assert String.starts_with?(opening, "    @doc")
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        @spec foo() :: :ok
        @doc "Line one.\\nLine two."
        def foo, do: :ok

        def bar, do: :error
      end
      """

      fixed = fix(code)
      assert fixed =~ "@spec foo() :: :ok"
      assert fixed =~ "def foo, do: :ok"
      assert fixed =~ "def bar, do: :error"
      assert fixed =~ ~S|@doc """|
    end

    test "handles escaped quotes in content" do
      code = """
      defmodule Example do
        @doc "Uses \\\"quotes\\\".\\nSecond line."
        def foo, do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@doc """|
      # The escaped quotes should become real quotes in heredoc
      assert fixed =~ ~S|Uses "quotes".|
    end

    test "does not modify single-line @doc" do
      code = """
      defmodule Example do
        @doc "Simple doc."
        def foo, do: :ok
      end
      """

      assert fix(code) == code
    end

    test "does not modify @doc with only trailing \\n" do
      code = """
      defmodule Example do
        @doc "Simple doc.\\n"
        def foo, do: :ok
      end
      """

      # Only trailing \n, no internal — not this rule's job
      assert fix(code) == code
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def foo, do: :ok
      end
      """

      assert fix(code) == code
    end

    test "fixes multiple doc attrs in one file" do
      code = """
      defmodule Example do
        @moduledoc "Module line1.\\nModule line2."

        @doc "Func line1.\\nFunc line2."
        def foo, do: :ok
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@moduledoc """|
      assert fixed =~ ~S|@doc """|
      assert fixed =~ "  Module line1."
      assert fixed =~ "  Func line1."
      refute fixed =~ "\\n"
    end

    test "handles LLM-style verbose doc with sections" do
      code = """
      defmodule Example do
        @doc "Counts occurrences.\\n\\n## Parameters\\n\\n- string: the input\\n- target: the char\\n"
        def count_char(s, t), do: 0
      end
      """

      fixed = fix(code)
      assert fixed =~ ~S|@doc """|
      assert fixed =~ "  Counts occurrences."
      assert fixed =~ "  ## Parameters"
      assert fixed =~ "  - string: the input"
      assert fixed =~ "  - target: the char"
      refute fixed =~ "\\n"
    end
  end

  defp check_with_source(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.ZzPreferHeredocForMultiLineDoc.check(ast, source: code)
  end

  defp analyze(code) do
    Credence.analyze(code, [])
  end

  describe "does not flag @doc already using heredoc" do
    test "heredoc @doc is not flagged (with source in opts)" do
      code = ~S'''
      defmodule Example do
        @doc """
        Checks if a string is a palindrome.

        ## Examples

            iex> Example.palindrome?("racecar")
            true
        """
        def palindrome?(s), do: s == String.reverse(s)
      end
      '''

      issues = check_with_source(code)

      heredoc_issues =
        Enum.filter(issues, &(&1.rule == :prefer_heredoc_for_multi_line_doc))

      assert heredoc_issues == [],
             "Heredoc @doc should not be flagged, but got: #{inspect(heredoc_issues)}"
    end

    test "heredoc @doc is not flagged via Credence.analyze" do
      code = ~S'''
      defmodule Example do
        @doc """
        Checks if a string is a palindrome.

        ## Examples

            iex> Example.palindrome?("racecar")
            true
        """
        def palindrome?(s), do: s == String.reverse(s)
      end
      '''

      %{issues: issues} = analyze(code)

      heredoc_issues =
        Enum.filter(issues, &(&1.rule == :prefer_heredoc_for_multi_line_doc))

      assert heredoc_issues == [],
             "Heredoc @doc should not be flagged by analyze, but got: #{inspect(heredoc_issues)}"
    end

    test "single-line @doc with \\n escapes IS still flagged" do
      code = ~S'''
      defmodule Example do
        @doc "Line one.\nLine two."
        def foo, do: :ok
      end
      '''

      issues = check_with_source(code)

      assert Enum.any?(issues, &(&1.rule == :prefer_heredoc_for_multi_line_doc)),
             "Single-line @doc with \\n should be flagged"
    end
  end
end
