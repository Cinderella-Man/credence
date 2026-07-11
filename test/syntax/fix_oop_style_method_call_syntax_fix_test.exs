defmodule Credence.Syntax.FixOopStyleMethodCallSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixOopStyleMethodCallSyntax

  defp analyze(code), do: FixOopStyleMethodCallSyntax.analyze(code)
  defp fix(code), do: FixOopStyleMethodCallSyntax.fix(code)

  test "fixes the syntax error" do
    input = "bucket.finalized?(bucket)"
    expected = "bucket.finalized?"

    confirm_fix(fix(input), expected)
  end

  test "fixes inside a larger expression" do
    input = "if not bucket.finalized?(bucket), do: start, else: :infinity"
    expected = "if not bucket.finalized?, do: start, else: :infinity"

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("bucket.finalized?(bucket)")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("bucket.finalized?(bucket)"))
  end
end
