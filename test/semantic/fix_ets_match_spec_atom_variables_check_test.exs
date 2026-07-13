defmodule Credence.Semantic.FixEtsMatchSpecAtomVariablesCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixEtsMatchSpecAtomVariables

  @real_diag %{
    severity: :error,
    message:
      "invalid syntax found on credence_check.ex:154:42:\n     error: unexpected token: \"$\" (column 42, code point U+0024)\n     │\n 154 │         {{:'$1', :'$2', :'_}, [{:'=<', :'$2', cutoff}], [true]}\n     │                                          ^\n     │\n     └─ credence_check.ex:154:42",
    position: 154,
    file: "credence_check.ex"
  }

  test "matches the diagnostic" do
    assert FixEtsMatchSpecAtomVariables.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute FixEtsMatchSpecAtomVariables.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixEtsMatchSpecAtomVariables.to_issue(@real_diag).rule ==
             :fix_ets_match_spec_atom_variables
  end
end
