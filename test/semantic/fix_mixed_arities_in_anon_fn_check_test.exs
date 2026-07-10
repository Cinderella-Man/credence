defmodule Credence.Semantic.FixMixedAritiesInAnonFnCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixMixedAritiesInAnonFn

  @real_diag %{
    severity: :error,
    message: "cannot mix clauses with different arities in anonymous functions",
    position: {144, 50},
    file: "credence_check.ex",
    source: "credence_check.ex",
    span: nil
  }

  test "matches the diagnostic" do
    assert FixMixedAritiesInAnonFn.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixMixedAritiesInAnonFn.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixMixedAritiesInAnonFn.to_issue(@real_diag).rule == :fix_mixed_arities_in_anon_fn
  end
end
