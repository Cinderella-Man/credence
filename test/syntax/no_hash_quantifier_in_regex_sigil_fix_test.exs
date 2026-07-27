defmodule Credence.Syntax.NoHashQuantifierInRegexSigilFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoHashQuantifierInRegexSigil

  defp analyze(code), do: NoHashQuantifierInRegexSigil.analyze(code)
  defp fix(code), do: NoHashQuantifierInRegexSigil.fix(code)

  test "rewrites a hash range quantifier to a character class" do
    code = ~S"""
    ~r/^#{1,6}\s+(.+)$/
    """

    expected = ~S"""
    ~r/^[#]{1,6}\s+(.+)$/
    """

    confirm_fix(fix(code), expected)
  end

  test "rewrites an open-ended quantifier" do
    code = ~S"""
    ~r/#{1,}/
    """

    expected = ~S"""
    ~r/[#]{1,}/
    """

    confirm_fix(fix(code), expected)
  end

  test "rewrites inside a module and leaves the rest of the source alone" do
    code = ~S"""
    defmodule HeadingParser do
      @heading ~r/^#{1,6}\s+(.+)$/

      def level(line), do: Regex.run(@heading, line)
    end
    """

    expected = ~S"""
    defmodule HeadingParser do
      @heading ~r/^[#]{1,6}\s+(.+)$/

      def level(line), do: Regex.run(@heading, line)
    end
    """

    confirm_fix(fix(code), expected)
  end

  test "rewrites every occurrence, including two sigils on one line" do
    code = ~S"""
    a = ~r/#{1,2}/
    b = ~r/x#{3,}/ <> ~r/y#{4,5}/
    """

    expected = ~S"""
    a = ~r/[#]{1,2}/
    b = ~r/x[#]{3,}/ <> ~r/y[#]{4,5}/
    """

    confirm_fix(fix(code), expected)
  end

  test "keeps an escaped forward slash in the sigil body" do
    code = ~S"""
    ~r/a\/b#{2,4}/
    """

    expected = ~S"""
    ~r/a\/b[#]{2,4}/
    """

    confirm_fix(fix(code), expected)
  end

  test "fixed output no longer flags" do
    code = ~S"""
    ~r/^#{1,6}\s+(.+)$/
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = ~S"""
    ~r/^#{1,6}\s+(.+)$/
    """

    assert valid_syntax?(fix(code))
  end

  test "the rewritten regex matches a literal hash run" do
    assert Regex.match?(~r/^[#]{1,6}\s+(.+)$/, "### Heading")
    refute Regex.match?(~r/^[#]{1,6}\s+(.+)$/, "Heading")
  end

  test "the syntax phase repairs the unparseable source end to end" do
    code = ~S"""
    defmodule HeadingParser do
      @heading ~r/^#{1,6}\s+(.+)$/
    end
    """

    expected = ~S"""
    defmodule HeadingParser do
      @heading ~r/^[#]{1,6}\s+(.+)$/
    end
    """

    refute valid_syntax?(code)
    confirm_fix(Credence.Syntax.fix(code), expected)
  end

  test "leaves already-correct code unchanged" do
    code = ~S"""
    ~r/^[#]{1,6}\s+(.+)$/
    """

    confirm_fix(fix(code), code)
  end

  test "leaves code without a regex sigil unchanged" do
    code = ~S"""
    def foo, do: :bar
    """

    confirm_fix(fix(code), code)
  end

  # --- deliberately skipped: valid code whose meaning we refuse to change ---

  test "leaves a bare hash-brace interpolation unchanged" do
    code = ~S"""
    ~r/x#{3}y/
    """

    confirm_fix(fix(code), code)
    assert valid_syntax?(code)
  end

  test "leaves an escaped hash quantifier unchanged" do
    code = ~S"""
    ~r/\#{1,6}/
    """

    confirm_fix(fix(code), code)
    assert valid_syntax?(code)
  end

  test "leaves ~R sigils unchanged" do
    code = ~S"""
    ~R/#{1,6}/
    """

    confirm_fix(fix(code), code)
    assert valid_syntax?(code)
  end

  test "leaves non-slash delimiters unchanged" do
    code = ~S"""
    ~r|#{1,6}|
    ~r{#{1,6}}
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a hash quantifier outside a sigil body unchanged" do
    code = ~S"""
    ~r/plain/ <> "#{1,2}"
    """

    confirm_fix(fix(code), code)
  end
end
