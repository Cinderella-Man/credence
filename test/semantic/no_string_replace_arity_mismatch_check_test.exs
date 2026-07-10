defmodule Credence.Semantic.NoStringReplaceArityMismatchCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoStringReplaceArityMismatch

  @real_message "no function clause matching in String.replace/4"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert NoStringReplaceArityMismatch.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoStringReplaceArityMismatch.match?(diag)
  end

  test "ignores unrelated String.replace errors" do
    diag = %{severity: :error, message: "String.replace/3 is undefined", position: {1, 1}}
    refute NoStringReplaceArityMismatch.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert NoStringReplaceArityMismatch.to_issue(diag).rule == :no_string_replace_arity_mismatch
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoStringReplaceArityMismatch.to_issue(diag).meta.line == 42
  end
end
