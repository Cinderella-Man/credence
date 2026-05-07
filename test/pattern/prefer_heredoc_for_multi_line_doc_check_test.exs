defmodule Credence.Pattern.PreferHeredocForMultiLineDocCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.PreferHeredocForMultiLineDoc.check(ast, [])
  end

  defp check_with_source(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.PreferHeredocForMultiLineDoc.check(ast, source: code)
  end

  defp analyze(code) do
    Credence.analyze(code, [])
  end

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

  describe "check/2 — does not flag existing heredocs" do
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

      heredoc_issues =
        code
        |> check_with_source()
        |> Enum.filter(&(&1.rule == :prefer_heredoc_for_multi_line_doc))

      assert heredoc_issues == []
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

      assert heredoc_issues == []
    end

    test "single-line @doc with \\n escapes IS still flagged" do
      code = ~S'''
      defmodule Example do
        @doc "Line one.\nLine two."
        def foo, do: :ok
      end
      '''

      assert Enum.any?(
               check_with_source(code),
               &(&1.rule == :prefer_heredoc_for_multi_line_doc)
             )
    end
  end
end
