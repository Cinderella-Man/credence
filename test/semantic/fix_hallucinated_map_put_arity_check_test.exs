defmodule Credence.Semantic.FixHallucinatedMapPutArityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedMapPutArity

  @real_message "Map.put/5 is undefined or private. Did you mean:\n\n    * put/3\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 9}}
    assert FixHallucinatedMapPutArity.match?(diag)
  end

  test "matches Map.put/4 diagnostic" do
    diag = %{severity: :warning, message: "Map.put/4 is undefined or private", position: {1, 1}}
    assert FixHallucinatedMapPutArity.match?(diag)
  end

  test "matches Map.put/7 diagnostic" do
    diag = %{severity: :warning, message: "Map.put/7 is undefined or private", position: {1, 1}}
    assert FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores Map.put/3 (correct arity)" do
    diag = %{severity: :warning, message: "some other Map.put/3 issue", position: {1, 1}}
    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 9}}
    assert FixHallucinatedMapPutArity.to_issue(diag).rule == :fix_hallucinated_map_put_arity
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert FixHallucinatedMapPutArity.to_issue(diag).meta.line == 42
  end
end
