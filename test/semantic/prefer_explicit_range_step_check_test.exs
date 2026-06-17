defmodule Credence.Semantic.PreferExplicitRangeStepCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferExplicitRangeStep

  @diagnostic %{
    severity: :warning,
    message: "1..-2 has a default step of -1, please write 1..-2//-1 instead",
    position: 0
  }

  test "matches the default-step warning" do
    assert PreferExplicitRangeStep.match?(@diagnostic)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferExplicitRangeStep.match?(diag)
  end

  test "ignores the redefining-module warning (the noise the first attempt fired on)" do
    diag = %{
      severity: :warning,
      message:
        "redefining module Config (current version loaded from .../Elixir.Config.beam)",
      position: 1
    }

    refute PreferExplicitRangeStep.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert PreferExplicitRangeStep.to_issue(@diagnostic).rule == :prefer_explicit_range_step
  end

  test "preserves the diagnostic message" do
    assert PreferExplicitRangeStep.to_issue(@diagnostic).message == @diagnostic.message
  end

  test "extracts line from tuple position" do
    diag = %{@diagnostic | position: {7, 3}}
    assert PreferExplicitRangeStep.to_issue(diag).meta.line == 7
  end
end
