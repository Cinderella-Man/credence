defmodule Credence.Semantic.FixRaiseInKeywordValueCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixRaiseInKeywordValue

  @diagnostic_msg "missing parentheses for expression following \"do:\" keyword. Parentheses are required to solve ambiguity inside keywords.\n\nThis error happens when you have function calls without parentheses inside keywords. For example:\n\n    function(arg, one: nested_call a, b, c)\n    function(arg, one: if expr, do: :this, else: :that)\n\nIn the examples above, we don't know if the arguments \"b\" and \"c\" apply to the function \"function\" or \"nested_call\". Or if the keywords \"do\" and \"else\" apply to the function \"function\" or \"if\". You can solve this by explicitly adding parentheses:\n\n    function(arg, one: if(expr, do: :this, else: :that))\n    function(arg, one: nested_call(a, b, c))\n\nAmbiguity found at:"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: {13, 1}}
    assert FixRaiseInKeywordValue.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixRaiseInKeywordValue.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: {13, 1}}
    assert FixRaiseInKeywordValue.to_issue(diag).rule == :fix_raise_in_keyword_value
  end
end
