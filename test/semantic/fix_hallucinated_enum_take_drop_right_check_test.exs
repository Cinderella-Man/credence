defmodule Credence.Semantic.FixHallucinatedEnumTakeDropRightCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedEnumTakeDropRight

  # Real diagnostic shape from `Code.with_diagnostics/1` compiling the flagship
  # input in the fix test — the column points at `take_right`.
  @take_message "Enum.take_right/2 is undefined or private. Did you mean:\n\n    * take/2\n"
  @drop_message "Enum.drop_right/2 is undefined or private. Did you mean:\n\n    * drop/2\n"
  @take_diag %{severity: :warning, message: @take_message, position: {3, 10}}
  @drop_diag %{severity: :warning, message: @drop_message, position: {3, 10}}

  test "matches the Enum.take_right/2 diagnostic" do
    assert FixHallucinatedEnumTakeDropRight.match?(@take_diag)
  end

  test "matches the Enum.drop_right/2 diagnostic" do
    assert FixHallucinatedEnumTakeDropRight.match?(@drop_diag)
  end

  test "matches the bare message without the Did-you-mean suffix" do
    diag = %{
      severity: :warning,
      message: "Enum.take_right/2 is undefined or private",
      position: {3, 10}
    }

    assert FixHallucinatedEnumTakeDropRight.match?(diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(@take_diag))

    assert winner == FixHallucinatedEnumTakeDropRight
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedEnumTakeDropRight.match?(diag)
  end

  test "ignores other arities (no two-argument rewrite applies)" do
    diag = %{
      severity: :warning,
      message: "Enum.take_right/3 is undefined or private",
      position: {2, 19}
    }

    refute FixHallucinatedEnumTakeDropRight.match?(diag)
  end

  test "ignores a user module whose path merely ends in Enum" do
    diag = %{
      severity: :warning,
      message: "MyEnum.take_right/2 is undefined or private",
      position: {2, 21}
    }

    refute FixHallucinatedEnumTakeDropRight.match?(diag)
  end

  test "ignores the unavailable-module wording for a missing module" do
    diag = %{
      severity: :warning,
      message:
        "MyEnum.take_right/2 is undefined (module MyEnum is not available or is yet to be defined)",
      position: {2, 21}
    }

    refute FixHallucinatedEnumTakeDropRight.match?(diag)
  end

  test "ignores error-severity diagnostics" do
    diag = %{severity: :error, message: @take_message, position: {3, 10}}
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
    assert FixHallucinatedEnumTakeDropRight.to_issue(@take_diag).message == @take_message
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @take_message, position: {42, 10}}
    assert FixHallucinatedEnumTakeDropRight.to_issue(diag).meta.line == 42
  end
end
