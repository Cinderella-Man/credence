defmodule Credence.Semantic.NoHallucinatedMapReduceCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedMapReduce

  test "matches the Map.reduce/3 diagnostic" do
    diag = %{severity: :warning, message: "Map.reduce/3 is undefined or private", position: {3, 9}}
    assert NoHallucinatedMapReduce.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedMapReduce.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedMapReduce.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: "Map.reduce/3 is undefined or private", position: {3, 9}}
    assert NoHallucinatedMapReduce.to_issue(diag).rule == :no_hallucinated_map_reduce
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: "Map.reduce/3 is undefined or private", position: {42, 10}}
    assert NoHallucinatedMapReduce.to_issue(diag).meta.line == 42
  end
end
