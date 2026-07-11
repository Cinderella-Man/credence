defmodule Credence.Syntax.FixOopStyleMethodCallSyntaxAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixOopStyleMethodCallSyntax

  defp analyze(code), do: FixOopStyleMethodCallSyntax.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :fix_oop_style_method_call_syntax, meta: %{line: 1}}] =
             analyze("bucket.finalized?(bucket)")
  end

  test "flags inside a larger expression" do
    code = "if not bucket.finalized?(bucket), do: start, else: :infinity"
    assert [%Issue{rule: :fix_oop_style_method_call_syntax}] = analyze(code)
  end

  test "leaves good code alone" do
    assert analyze("bucket.finalized?") == []
  end

  test "leaves normal function call alone" do
    assert analyze(~S'IO.puts("hello")') == []
  end

  test "leaves different-variable call alone" do
    assert analyze("bucket.finalized?(other)") == []
  end
end
