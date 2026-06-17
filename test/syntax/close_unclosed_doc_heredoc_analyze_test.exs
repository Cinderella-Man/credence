defmodule Credence.Syntax.CloseUnclosedDocHeredocAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.CloseUnclosedDocHeredoc

  defp analyze(code), do: CloseUnclosedDocHeredoc.analyze(code)

  test "flags unclosed @doc heredoc before def" do
    assert [%Issue{rule: :close_unclosed_doc_heredoc, meta: %{line: 2}}] =
             analyze("""
             defmodule Solution do
               @doc \"""
               def find_min_max(list) do
                 Enum.min_max(list)
               end
             end
             """)
  end

  test "flags unclosed @doc heredoc with blank lines before def" do
    assert [%Issue{rule: :close_unclosed_doc_heredoc, meta: %{line: 2}}] =
             analyze("""
             defmodule Solution do
               @doc \"""

               def find_min_max(list) do
                 Enum.min_max(list)
               end
             end
             """)
  end

  test "leaves properly closed @doc heredoc alone" do
    assert analyze("""
           defmodule Solution do
             @doc \"\"\"
             Finds the min and max.
             \"\"\"
             def find_min_max(list) do
               Enum.min_max(list)
             end
           end
           """) == []
  end

  test "leaves code without @doc heredoc alone" do
    assert analyze("""
           defmodule Solution do
             def find_min_max(list) do
               Enum.min_max(list)
             end
           end
           """) == []
  end

  test "leaves @doc string literal alone" do
    assert analyze("""
           defmodule Solution do
             @doc "Finds the min and max."
             def find_min_max(list) do
               Enum.min_max(list)
             end
           end
           """) == []
  end

  test "ignores @doc heredoc not followed by def" do
    assert analyze("""
           @doc \"""
           Some module attribute
           @other_attr :value
           """) == []
  end
end
