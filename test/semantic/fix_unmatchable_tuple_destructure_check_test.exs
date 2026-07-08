defmodule Credence.Semantic.FixUnmatchableTupleDestructureCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUnmatchableTupleDestructure

  @real_message "misplaced operator |/2\n\nThe | operator is typically used between brackets to mark the tail of a list:\n\n    [head | tail]\n    [head, middle, ... | tail]\n\nIt is also used to update maps and structs, via the %{map | key: value} notation, and in typespecs, such as @type and @spec, to express the union of two types"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {216, 36}, file: "credence_check.ex", stacktrace: [{SoftCrud.Documents, :validate_attrs, 2, [file: "credence_check.ex", column: 36, line: 216]}], source: "credence_check.ex", span: nil}
    assert FixUnmatchableTupleDestructure.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixUnmatchableTupleDestructure.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0
    }

    refute FixUnmatchableTupleDestructure.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {216, 36}}

    assert FixUnmatchableTupleDestructure.to_issue(diag).rule ==
             :fix_unmatchable_tuple_destructure
  end

  test "preserves the line in the issue" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert FixUnmatchableTupleDestructure.to_issue(diag).meta.line == 42
  end
end
