defmodule Credence.Semantic.NoDiscardedUnlessValueCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDiscardedUnlessValue

  @real_message "unless expression result is unused"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    assert NoDiscardedUnlessValue.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoDiscardedUnlessValue.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    assert NoDiscardedUnlessValue.to_issue(diag).rule == :no_discarded_unless_value
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 5}}
    assert NoDiscardedUnlessValue.to_issue(diag).meta.line == 42
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute NoDiscardedUnlessValue.match?(diag)
  end
end
