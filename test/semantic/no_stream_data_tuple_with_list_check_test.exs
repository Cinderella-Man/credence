defmodule Credence.Semantic.NoStreamDataTupleWithListCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoStreamDataTupleWithList

  @real_message "no function clause matching in StreamData.tuple/1"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {9, 7}}
    assert NoStreamDataTupleWithList.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoStreamDataTupleWithList.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute NoStreamDataTupleWithList.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {9, 7}}
    assert NoStreamDataTupleWithList.to_issue(diag).rule == :no_stream_data_tuple_with_list
  end

  test "preserves the line in the issue" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoStreamDataTupleWithList.to_issue(diag).meta.line == 42
  end
end
