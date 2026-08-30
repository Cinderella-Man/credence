defmodule Credence.Syntax.NoUnclosedFnDelimiterAnalyzeTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Issue
  alias Credence.Syntax.NoUnclosedFnDelimiter

  defp analyze(code), do: NoUnclosedFnDelimiter.analyze(code)

  test "flags an fn closed with ) instead of end" do
    assert [%Issue{rule: :no_unclosed_fn_delimiter, meta: %{line: 1}}] =
             analyze("list |> Enum.max_by(fn {_, second} -> second)")
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

  test "reports every unclosed fn delimiter repaired in the same source" do
    source = """
    defmodule NoUnclosedFnDelimiterMultipleAnalyzeFixture do
      def a(list), do: Enum.map(list, fn x -> x + 1)
      def b(list), do: Enum.filter(list, fn x -> x > 0)
    end
    """

    assert analyze(source) == [
             %Issue{
               rule: :no_unclosed_fn_delimiter,
               message: "`fn` block closed with `)` instead of `end`; insert the missing `end`.",
               meta: %{line: 2}
             },
             %Issue{
               rule: :no_unclosed_fn_delimiter,
               message: "`fn` block closed with `)` instead of `end`; insert the missing `end`.",
               meta: %{line: 3}
             }
           ]

    confirm_fix(NoUnclosedFnDelimiter.fix(source), """
    defmodule NoUnclosedFnDelimiterMultipleAnalyzeFixture do
      def a(list), do: Enum.map(list, fn x -> x + 1 end)
      def b(list), do: Enum.filter(list, fn x -> x > 0 end)
    end
    """)
  end

  test "does not flag a properly closed fn" do
    assert analyze("list |> Enum.max_by(fn {_, second} -> second end)") == []
  end

  test "does not flag valid code that ends in )" do
    assert analyze("list |> Enum.map(fn x -> x + 1 end) |> Enum.sum()") == []
  end

  test "does not flag a different mismatched delimiter" do
    # `[` closed by `)` — a real mismatch, but not an fn/end one.
    assert analyze("value = [1, 2, 3)") == []
  end

  # The rule only fires when inserting `end` actually repairs the source. The
  # cases below are also `fn … )` mismatched delimiters, but they are a
  # different malformation (no `args -> body`), so inserting `end` would NOT
  # yield valid code — the rule must leave them for another rule and flag
  # nothing.

  test "does not flag fn(&1 ...) capture-mixing (owned by NoFnWithCapture)" do
    assert analyze("Enum.filter(list, fn(&1 > 0))") == []
  end

  test "does not flag an arrowless fn closed with )" do
    assert analyze("Enum.map(list, fn x)") == []
  end

  test "does not flag a bare fn with no args or arrow" do
    assert analyze("foo(fn)") == []
  end

  test "does not flag an arrowless multi-arg fn" do
    assert analyze("Enum.map(list, fn x, y)") == []
  end
end
