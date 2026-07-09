defmodule Credence.Semantic.NoUnusedPrivateFunctionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnusedPrivateFunction

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: "function unused_helper/0 is unused", position: {3, 3}}
    assert NoUnusedPrivateFunction.match?(diag)
  end

  test "matches with different function names and arities" do
    diag = %{severity: :warning, message: "function calculate_sum/2 is unused", position: {5, 3}}
    assert NoUnusedPrivateFunction.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated warning", position: {1, 1}}
    refute NoUnusedPrivateFunction.match?(diag)
  end

  test "ignores non-warning diagnostics" do
    diag = %{severity: :error, message: "function unused_helper/0 is unused", position: {3, 3}}
    refute NoUnusedPrivateFunction.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: "function unused_helper/0 is unused", position: {3, 3}}
    assert NoUnusedPrivateFunction.to_issue(diag).rule == :no_unused_private_function
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: "function unused_helper/0 is unused", position: {7, 5}}
    assert NoUnusedPrivateFunction.to_issue(diag).meta.line == 7
  end
end
