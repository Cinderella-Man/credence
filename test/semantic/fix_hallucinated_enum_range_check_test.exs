defmodule Credence.Semantic.FixHallucinatedEnumRangeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedEnumRange

  @diag %{severity: :warning, message: "Enum.range/2 is undefined or private", position: {4, 18}}

  test "matches the Enum.range/2 diagnostic" do
    assert FixHallucinatedEnumRange.match?(@diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
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
    diag = %{severity: :warning, message: "Enum.range/2 is undefined or private", position: {42, 10}}
    assert FixHallucinatedEnumRange.to_issue(diag).meta.line == 42
  end
end
