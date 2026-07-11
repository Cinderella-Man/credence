defmodule Credence.Pattern.FixStringReplaceMultiArityFnFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixStringReplaceMultiArityFn

  test "rewrites the anti-pattern by removing trailing []" do
    input = ~S'String.replace("abc", ~r/\d/, fn match, acc -> {"*", acc} end, [])'

    expected = ~S'String.replace("abc", ~r/\d/, fn match, acc -> {"*", acc} end)'

    confirm_fix(fix(FixStringReplaceMultiArityFn, input), expected)
  end

  test "rewrites multi-line fn" do
    input = ~S"""
    String.replace("abc123", ~r/\d/, fn match, acc ->
      {"*", acc}
    end, [])
    """

    expected = ~S"""
    String.replace("abc123", ~r/\d/, fn match, acc ->
      {"*", acc}
    end)
    """

    confirm_fix(fix(FixStringReplaceMultiArityFn, input), expected)
  end
end
