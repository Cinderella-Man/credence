defmodule Credence.Semantic.NoHallucinatedPersistentTermFnCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedPersistentTermFn

  @real_message "clauses with the same name and arity (number of arguments) should be grouped together, \"def handle_call/3\" was previously defined (credence_check.ex:90)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {123, 7}, file: "credence_check.ex"}
    assert NoHallucinatedPersistentTermFn.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedPersistentTermFn.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedPersistentTermFn.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {123, 7}, file: "credence_check.ex"}
    assert NoHallucinatedPersistentTermFn.to_issue(diag).rule == :no_hallucinated_persistent_term_fn
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}, file: "credence_check.ex"}
    assert NoHallucinatedPersistentTermFn.to_issue(diag).meta.line == 42
  end
end
