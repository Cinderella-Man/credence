defmodule Credence.Semantic.NoHallucinatedErlangWarnCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedErlangWarn

  @real_message ":erlang.warn/1 is undefined or private"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {9, 18}}
    assert NoHallucinatedErlangWarn.match?(diag)
  end

  test "matches the diagnostic with hint" do
    diag = %{severity: :warning, message: ":erlang.warn/1 is undefined or private. Did you mean:\n\n    * warning/2\n", position: {9, 18}}
    assert NoHallucinatedErlangWarn.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedErlangWarn.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Example (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedErlangWarn.match?(diag)
  end

  test "ignores :erlang.display warning" do
    diag = %{severity: :warning, message: ":erlang.display/1 is undefined or private", position: {1, 1}}
    refute NoHallucinatedErlangWarn.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {9, 18}}
    assert NoHallucinatedErlangWarn.to_issue(diag).rule == :no_hallucinated_erlang_warn
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoHallucinatedErlangWarn.to_issue(diag).meta.line == 42
  end
end
