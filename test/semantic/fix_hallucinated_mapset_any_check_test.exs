defmodule Credence.Semantic.FixHallucinatedMapsetAnyCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedMapsetAny

  @diagnostic_message "MapSet.any?/2 is undefined or private"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @diagnostic_message, position: {96, 26}}
    assert FixHallucinatedMapsetAny.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedMapsetAny.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixHallucinatedMapsetAny.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @diagnostic_message, position: {96, 26}}
    assert FixHallucinatedMapsetAny.to_issue(diag).rule == :fix_hallucinated_mapset_any
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @diagnostic_message, position: {42, 10}}
    assert FixHallucinatedMapsetAny.to_issue(diag).meta.line == 42
  end
end
