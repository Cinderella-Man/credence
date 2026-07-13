defmodule Credence.Semantic.FixTaskAsyncStreamCaseMatchCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixTaskAsyncStreamCaseMatch

  @ok_message "the following clause will never match:\n\n    {:ok, results}\n\nbecause it attempts to match on the result of:\n\n    Task.async_stream(elements, fun, max_concurrency: 4)\n\nwhich has type:\n\n    dynamic((term(), term() -> term()))\n"
  @error_message "the following clause will never match:\n\n    {:error, reason}\n\nbecause it attempts to match on the result of:\n\n    Task.async_stream(elements, fun, max_concurrency: 4)\n\nwhich has type:\n\n    dynamic((term(), term() -> term()))\n"

  test "matches the diagnostic for {:ok, results} clause" do
    diag = %{severity: :warning, message: @ok_message, position: {4, 5}}
    assert FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "matches the diagnostic for {:error, reason} clause" do
    diag = %{severity: :warning, message: @error_message, position: {6, 5}}
    assert FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @ok_message, position: {4, 5}}
    assert FixTaskAsyncStreamCaseMatch.to_issue(diag).rule == :fix_task_async_stream_case_match
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @ok_message, position: {42, 5}}
    assert FixTaskAsyncStreamCaseMatch.to_issue(diag).meta.line == 42
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @ok_message, position: {1, 1}}
    refute FixTaskAsyncStreamCaseMatch.match?(diag)
  end
end
