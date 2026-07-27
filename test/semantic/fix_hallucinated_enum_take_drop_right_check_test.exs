defmodule Credence.Semantic.FixHallucinatedEnumTakeDropRightCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedEnumTakeDropRight

  @take_diag %{severity: :warning, message: "Enum.take_right/2 is undefined or private", position: {3, 5}}
  @drop_diag %{severity: :warning, message: "Enum.drop_right/2 is undefined or private", position: {7, 5}}

  test "matches the Enum.take_right/2 diagnostic" do
    assert FixHallucinatedEnumTakeDropRight.match?(@take_diag)
  end

  test "matches the Enum.drop_right/2 diagnostic" do
    assert FixHallucinatedEnumTakeDropRight.match?(@drop_diag)
  end

  test "matches undefined function variant" do
    diag = %{severity: :warning, message: "Enum.take_right/2 is undefined function", position: {1, 1}}
    assert FixHallucinatedEnumTakeDropRight.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedEnumTakeDropRight.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixHallucinatedEnumTakeDropRight.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixHallucinatedEnumTakeDropRight.to_issue(@take_diag).rule ==
             :fix_hallucinated_enum_take_drop_right
  end

  test "preserves the original message in the issue" do
    assert FixHallucinatedEnumTakeDropRight.to_issue(@take_diag).message ==
             "Enum.take_right/2 is undefined or private"
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: "Enum.take_right/2 is undefined or private", position: {42, 10}}
    assert FixHallucinatedEnumTakeDropRight.to_issue(diag).meta.line == 42
  end
end
