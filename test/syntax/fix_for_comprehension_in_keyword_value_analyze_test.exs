defmodule Credence.Syntax.FixForComprehensionInKeywordValueAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixForComprehensionInKeywordValue

  defp analyze(code), do: FixForComprehensionInKeywordValue.analyze(code)

  test "flags a bare for comprehension as a keyword value in a map" do
    code = "%{foo: for x <- [1,2,3], into: %{}, do: {x, x}}"
    assert [%Issue{rule: :fix_for_comprehension_in_keyword_value}] = analyze(code)
  end

  test "flags a bare for comprehension as a keyword value in a keyword list" do
    code = "[foo: for x <- [1,2,3], into: %{}, do: {x, x}]"
    assert [%Issue{rule: :fix_for_comprehension_in_keyword_value}] = analyze(code)
  end

  test "flags a bare for comprehension as a keyword value in a tuple" do
    code = "{:ok, for x <- [1,2,3], into: %{}, do: {x, x}}"
    assert [%Issue{rule: :fix_for_comprehension_in_keyword_value}] = analyze(code)
  end

  test "leaves parenthesized for comprehension alone" do
    code = "%{foo: (for x <- [1,2,3], into: %{}, do: {x, x})}"
    assert analyze(code) == []
  end

  test "leaves valid code alone" do
    code = "%{foo: 1 + 2}"
    assert analyze(code) == []
  end

  test "leaves bare for (not in keyword value) alone" do
    code = "for x <- [1,2,3], into: %{}, do: {x, x}"
    assert analyze(code) == []
  end

  test "does not flag if-in-keyword (handled by no_keyword_if_bare_in_tuple)" do
    code = "%{foo: if x > 0, do: :pos, else: :neg}"
    assert analyze(code) == []
  end
end
