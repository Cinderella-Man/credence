defmodule Credence.Semantic.NoAtomPositionInListKeyFunctionsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoAtomPositionInListKeyFunctions

  @real_message "redefining module Clock (current version loaded from _build/test/lib/workspace/ebin/Elixir.Clock.beam)"
  @real_diag %{
    message: @real_message,
    position: 1,
    file: "credence_check.ex",
    stacktrace: [{Clock, :__MODULE__, 0, [file: "credence_check.ex", line: 1]}],
    source: "credence_check.ex",
    span: nil,
    severity: :warning
  }

  test "matches the diagnostic" do
    assert NoAtomPositionInListKeyFunctions.match?(@real_diag)
  end

  test "matches module redefinition without version info" do
    diag = %{severity: :warning, message: "redefining module Foo", position: {1, 1}}
    assert NoAtomPositionInListKeyFunctions.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoAtomPositionInListKeyFunctions.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message:
        "credence_check.ex: cannot compile module Clock (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoAtomPositionInListKeyFunctions.match?(diag)
  end

  test "ignores :error severity" do
    diag = %{severity: :error, message: "redefining module Clock", position: {1, 1}}
    refute NoAtomPositionInListKeyFunctions.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoAtomPositionInListKeyFunctions.to_issue(@real_diag).rule ==
             :no_atom_position_in_list_key_functions
  end

  test "sets the line in issue meta" do
    assert NoAtomPositionInListKeyFunctions.to_issue(@real_diag).meta.line == 1
  end

  test "issue message mentions the root cause" do
    msg = NoAtomPositionInListKeyFunctions.to_issue(@real_diag).message
    assert String.contains?(msg, "List.keytake")
    assert String.contains?(msg, "integer position")
  end
end
