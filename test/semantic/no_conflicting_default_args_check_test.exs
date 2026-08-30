defmodule Credence.Semantic.NoConflictingDefaultArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoConflictingDefaultArgs

  @real_message "def sequence/1 conflicts with defaults from sequence/2"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {6, 3}}
    assert NoConflictingDefaultArgs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "undefined function foo/1", position: {1, 1}}
    refute NoConflictingDefaultArgs.match?(diag)
  end

  test "ignores malformed conflict diagnostics" do
    diag = %{
      severity: :error,
      message: "malformed conflicts with defaults from diagnostic",
      position: {1, 1}
    }

    refute NoConflictingDefaultArgs.match?(diag)
  end

  test "ignores warning severity" do
    diag = %{severity: :warning, message: @real_message, position: {6, 3}}
    refute NoConflictingDefaultArgs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {6, 3}}
    assert NoConflictingDefaultArgs.to_issue(diag).rule == :no_conflicting_default_args
  end

  test "extracts the conflicting arity in the issue message" do
    diag = %{severity: :error, message: @real_message, position: {6, 3}}

    assert NoConflictingDefaultArgs.to_issue(diag).message ==
             "def sequence/1 conflicts with defaults"
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {6, 3}}
    assert NoConflictingDefaultArgs.to_issue(diag).meta.line == 6
  end

  test "parses predicate function names accepted by the diagnostic matcher" do
    diag = %{
      severity: :error,
      message: "def ready?/1 conflicts with defaults from ready?/2",
      position: {4, 2}
    }

    assert NoConflictingDefaultArgs.match?(diag)

    assert NoConflictingDefaultArgs.to_issue(diag).message ==
             "def ready?/1 conflicts with defaults"
  end
end
