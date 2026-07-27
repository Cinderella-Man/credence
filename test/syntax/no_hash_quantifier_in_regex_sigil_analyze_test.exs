defmodule Credence.Syntax.NoHashQuantifierInRegexSigilAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoHashQuantifierInRegexSigil

  defp analyze(code), do: NoHashQuantifierInRegexSigil.analyze(code)

  test "flags a regex sigil with a hash range quantifier" do
    code = ~S"""
    ~r/^#{1,6}\s+(.+)$/
    """

    assert [%Issue{rule: :no_hash_quantifier_in_regex_sigil, meta: %{line: 1}}] = analyze(code)
  end

  test "flags an open-ended hash quantifier" do
    code = ~S"""
    ~r/#{1,}/
    """

    assert [%Issue{meta: %{line: 1}}] = analyze(code)
  end

  test "reports the correct line number" do
    code = ~S"""
    defmodule HeadingParser do
      def heading do
        ~r/^#{1,6}\s+(.+)$/
      end
    end
    """

    assert [%Issue{meta: %{line: 3}}] = analyze(code)
  end

  test "flags multiple occurrences" do
    code = ~S"""
    ~r/^#{1,6}\s/
    ~r/#{2,4}$/
    """

    assert [%Issue{meta: %{line: 1}}, %Issue{meta: %{line: 2}}] = analyze(code)
  end

  test "leaves already-fixed code alone" do
    code = ~S"""
    ~r/^[#]{1,6}\s+(.+)$/
    """

    assert analyze(code) == []
  end

  test "leaves a regex without a hash quantifier alone" do
    code = ~S"""
    ~r/^#.+$/
    """

    assert analyze(code) == []
  end

  test "leaves non-regex code alone" do
    code = ~S"""
    def foo, do: :bar
    """

    assert analyze(code) == []
  end

  test "does not flag hash in regular string interpolation" do
    code = ~S"""
    "#{name}"
    """

    assert analyze(code) == []
  end

  # --- deliberately skipped: valid code whose meaning we refuse to change ---

  test "no issue for a bare hash-brace in a sigil: that is valid interpolation" do
    code = ~S"""
    ~r/x#{3}y/
    """

    assert analyze(code) == []
  end

  test "no issue for an escaped hash quantifier: it already parses" do
    code = ~S"""
    ~r/\#{1,6}/
    """

    assert analyze(code) == []
  end

  test "no issue for ~R, which does not interpolate" do
    code = ~S"""
    ~R/#{1,6}/
    """

    assert analyze(code) == []
  end

  test "no issue for a sigil with a non-slash delimiter, which the fix skips" do
    code = ~S"""
    ~r|#{1,6}|
    ~r{#{1,6}}
    """

    assert analyze(code) == []
  end

  test "no issue for a hash quantifier outside any regex sigil body" do
    code = ~S"""
    ~r/plain/ <> "#{1,2}"
    """

    assert analyze(code) == []
  end
end
