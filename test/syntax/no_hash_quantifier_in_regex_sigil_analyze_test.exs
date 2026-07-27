defmodule Credence.Syntax.NoHashQuantifierInRegexSigilAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoHashQuantifierInRegexSigil

  defp analyze(code), do: NoHashQuantifierInRegexSigil.analyze(code)

  test "flags a regex sigil with hash quantifier" do
    assert [%Issue{rule: :no_hash_quantifier_in_regex_sigil, meta: %{line: 1}}] =
             analyze("~r/^\#{1,6}\\s+(.+)$/")
  end

  test "reports the correct line number" do
    source = """
    defmodule HeadingParser do
      def heading do
        ~r/^\#{1,6}\\s+(.+)$/
      end
    end
    """

    assert [%Issue{meta: %{line: 3}}] = analyze(source)
  end

  test "flags multiple occurrences" do
    source = """
    ~r/^\#{1,6}\\s/
    ~r/\#{2,4}$/
    """

    assert [%Issue{meta: %{line: 1}}, %Issue{meta: %{line: 2}}] = analyze(source)
  end

  test "leaves already-fixed code alone" do
    assert analyze("~r/^[#]{1,6}\\s+(.+)$/") == []
  end

  test "leaves regex without hash quantifier alone" do
    assert analyze("~r/^#.+$/") == []
  end

  test "leaves non-regex code alone" do
    assert analyze("def foo, do: :bar") == []
  end

  test "does not flag hash in regular string interpolation" do
    assert analyze(~S'"#{name}"') == []
  end
end
