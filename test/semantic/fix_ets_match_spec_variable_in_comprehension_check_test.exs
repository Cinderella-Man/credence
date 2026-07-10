defmodule Credence.Semantic.FixEtsMatchSpecVariableInComprehensionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixEtsMatchSpecVariableInComprehension

  @real_diag %{
    severity: :error,
    message: "undefined variable \"name\"",
    position: {42, 52},
    file: "credence_check.ex"
  }

  test "matches the diagnostic" do
    assert FixEtsMatchSpecVariableInComprehension.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixEtsMatchSpecVariableInComprehension.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixEtsMatchSpecVariableInComprehension.to_issue(@real_diag).rule ==
             :fix_ets_match_spec_variable_in_comprehension
  end
end
