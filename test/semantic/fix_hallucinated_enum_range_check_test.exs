defmodule Credence.Semantic.FixHallucinatedEnumRangeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedEnumRange

  # Real diagnostic shape from `Code.with_diagnostics/1` compiling the flagship
  # input in the fix test — the column points at `range`.
  @message "Enum.range/2 is undefined or private"
  @diag %{severity: :warning, message: @message, position: {4, 12}}

  test "matches the Enum.range/2 diagnostic" do
    assert FixHallucinatedEnumRange.match?(@diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(@diag))

    assert winner == FixHallucinatedEnumRange
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedEnumRange.match?(diag)
  end

  test "ignores other arities (Enum.range/3 has no two-endpoint literal)" do
    diag = %{
      severity: :warning,
      message: "Enum.range/3 is undefined or private",
      position: {2, 19}
    }

    refute FixHallucinatedEnumRange.match?(diag)
  end

  test "ignores a user module whose path merely ends in Enum" do
    diag = %{
      severity: :warning,
      message: "MyEnum.range/2 is undefined or private",
      position: {2, 21}
    }

    refute FixHallucinatedEnumRange.match?(diag)
  end

  test "ignores the unavailable-module wording for a missing module" do
    diag = %{
      severity: :warning,
      message:
        "MyEnum.range/2 is undefined (module MyEnum is not available or is yet to be defined)",
      position: {2, 21}
    }

    refute FixHallucinatedEnumRange.match?(diag)
  end

  test "ignores error-severity diagnostics" do
    diag = %{severity: :error, message: @message, position: {4, 12}}
    refute FixHallucinatedEnumRange.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixHallucinatedEnumRange.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixHallucinatedEnumRange.to_issue(@diag).rule == :fix_hallucinated_enum_range
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @message, position: {42, 10}}
    assert FixHallucinatedEnumRange.to_issue(diag).meta.line == 42
  end
end
