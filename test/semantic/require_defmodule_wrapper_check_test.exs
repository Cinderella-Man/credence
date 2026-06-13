defmodule Credence.Semantic.RequireDefmoduleWrapperCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.RequireDefmoduleWrapper

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: "cannot invoke @doc/1 outside module", position: {1, 1}}
    assert RequireDefmoduleWrapper.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute RequireDefmoduleWrapper.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: "cannot invoke @doc/1 outside module", position: {1, 1}}
    assert RequireDefmoduleWrapper.to_issue(diag).rule == :require_defmodule_wrapper
  end

  test "matches the redefining @moduledoc diagnostic" do
    diag = %{severity: :warning, message: "redefining @moduledoc attribute previously set at line 2", position: {6, 1}}
    assert RequireDefmoduleWrapper.match?(diag)
  end

  test "matches the redefining @doc diagnostic" do
    diag = %{severity: :warning, message: "redefining @doc attribute previously set at line 2", position: 5, file: "credence_check.ex", stacktrace: [{Solution, :__MODULE__, 0, [file: ~c"credence_check.ex", line: 5]}], source: "credence_check.ex", span: nil}
    assert RequireDefmoduleWrapper.match?(diag)
  end
end