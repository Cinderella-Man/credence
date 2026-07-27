defmodule Credence.Semantic.FixFnArityInKeywordValueCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixFnArityInKeywordValue

  @real_diag %{
    severity: :warning,
    message:
      "incompatible types given to Kernel.//2:\n\n    :push / 4\n\ngiven types:\n\n    -:push-, integer()\n\nbut expected one of:\n\n    float() or integer(), float() or integer()\n",
    position: {38, 49}
  }

  test "matches the diagnostic" do
    assert FixFnArityInKeywordValue.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixFnArityInKeywordValue.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixFnArityInKeywordValue.to_issue(@real_diag).rule == :fix_fn_arity_in_keyword_value
  end
end
