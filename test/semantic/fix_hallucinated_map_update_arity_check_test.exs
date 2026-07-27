defmodule Credence.Semantic.FixHallucinatedMapUpdateArityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedMapUpdateArity

  @real_message "Map.update/3 is undefined or private. Did you mean:\n\n    * update/4\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 9}}
    assert FixHallucinatedMapUpdateArity.match?(diag)
  end

  test "matches Map.update/3 diagnostic without Did you mean" do
    diag = %{severity: :warning, message: "Map.update/3 is undefined or private", position: {1, 1}}
    assert FixHallucinatedMapUpdateArity.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedMapUpdateArity.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixHallucinatedMapUpdateArity.match?(diag)
  end

  test "ignores Map.update/4 (correct arity)" do
    diag = %{severity: :warning, message: "some other Map.update/4 issue", position: {1, 1}}
    refute FixHallucinatedMapUpdateArity.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 9}}
    assert FixHallucinatedMapUpdateArity.to_issue(diag).rule == :fix_hallucinated_map_update_arity
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert FixHallucinatedMapUpdateArity.to_issue(diag).meta.line == 42
  end
end
