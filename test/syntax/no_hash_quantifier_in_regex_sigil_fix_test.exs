defmodule Credence.Syntax.NoHashQuantifierInRegexSigilFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoHashQuantifierInRegexSigil

  defp analyze(code), do: NoHashQuantifierInRegexSigil.analyze(code)
  defp fix(code), do: NoHashQuantifierInRegexSigil.fix(code)

  test "fixes hash-quantifier to character-class-quantifier" do
    input = "~r/^\#{1,6}\\s+(.+)$/"
    expected = "~r/^[#]{1,6}\\s+(.+)$/"

    confirm_fix(fix(input), expected)
  end

  test "fixes exact count quantifier" do
    input = "~r/^\#{3}abc$/"
    expected = "~r/^[#]{3}abc$/"

    confirm_fix(fix(input), expected)
  end

  test "fixes open-ended quantifier" do
    input = "~r/\#{1,}/"
    expected = "~r/[#]{1,}/"

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("~r/^\#{1,6}\\s+(.+)$/")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("~r/^\#{1,6}\\s+(.+)$/"))
  end

  test "leaves already-correct code unchanged" do
    code = "~r/^[#]{1,6}\\s+(.+)$/"
    confirm_fix(fix(code), code)
  end

  test "leaves code without regex sigil unchanged" do
    code = "def foo, do: :bar"
    confirm_fix(fix(code), code)
  end
end
