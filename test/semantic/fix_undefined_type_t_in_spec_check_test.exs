defmodule Credence.Semantic.FixUndefinedTypeTInSpecCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUndefinedTypeTInSpec

  @real_message "Saga.__struct__/1 is undefined (module Saga is not available)type t/0 is undefined (no such type in Saga)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {5, 1}, file: "credence_check.ex"}
    assert FixUndefinedTypeTInSpec.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}, file: "credence_check.ex"}
    refute FixUndefinedTypeTInSpec.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixUndefinedTypeTInSpec.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {5, 1}, file: "credence_check.ex"}
    assert FixUndefinedTypeTInSpec.to_issue(diag).rule == :fix_undefined_type_t_in_spec
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}, file: "credence_check.ex"}
    assert FixUndefinedTypeTInSpec.to_issue(diag).meta.line == 42
  end

  test "ignores warning severity" do
    diag = %{severity: :warning, message: @real_message, position: {5, 1}, file: "credence_check.ex"}
    refute FixUndefinedTypeTInSpec.match?(diag)
  end
end
