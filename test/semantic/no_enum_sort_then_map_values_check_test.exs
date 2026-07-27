defmodule Credence.Semantic.NoEnumSortThenMapValuesCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoEnumSortThenMapValues

  @real_message "the result of evaluating operator '+'/2 is ignored (suppress the warning by assigning the expression to the _ variable)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {133, 27}}
    assert NoEnumSortThenMapValues.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoEnumSortThenMapValues.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {133, 27}}
    assert NoEnumSortThenMapValues.to_issue(diag).rule == :no_enum_sort_then_map_values
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoEnumSortThenMapValues.to_issue(diag).meta.line == 42
  end
end
