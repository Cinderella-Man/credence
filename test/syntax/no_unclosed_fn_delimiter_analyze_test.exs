defmodule Credence.Syntax.NoUnclosedFnDelimiterAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoUnclosedFnDelimiter

  defp analyze(code), do: NoUnclosedFnDelimiter.analyze(code)

  test "flags an fn closed with ) instead of end" do
    assert [%Issue{rule: :no_unclosed_fn_delimiter, meta: %{line: 1}}] =
             analyze("""
             list |> Enum.max_by(fn {_, second} -> second)
             """)
  end

  test "reports the line of the offending )" do
    assert [%Issue{rule: :no_unclosed_fn_delimiter, meta: %{line: 3}}] =
             analyze("""
             defmodule Solution do
               def top(list) do
                 list |> Enum.max_by(fn {_, second} -> second)
               end
             end
             """)
  end

  test "does not flag a properly closed fn" do
    assert analyze("""
           list |> Enum.max_by(fn {_, second} -> second end)
           """) == []
  end

  test "does not flag valid code that ends in )" do
    assert analyze("""
           list |> Enum.map(fn x -> x + 1 end) |> Enum.sum()
           """) == []
  end

  test "does not flag a different mismatched delimiter" do
    # `[` closed by `)` — a real mismatch, but not an fn/end one.
    assert analyze("""
           value = [1, 2, 3)
           """) == []
  end
end
