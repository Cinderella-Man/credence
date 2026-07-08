defmodule Credence.Semantic.NoBareReturnKeywordCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoBareReturnKeyword

  @diagnostic %{
    severity: :error,
    message: "undefined variable \"return\"",
    position: {27, 7},
    file: "credence_check.ex",
    source: "credence_check.ex",
    span: {27, 13}
  }

  test "matches the diagnostic" do
    assert NoBareReturnKeyword.match?(@diagnostic)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoBareReturnKeyword.match?(diag)
  end

  test "ignores warnings with matching message" do
    diag = %{severity: :warning, message: "undefined variable \"return\"", position: {1, 1}}
    refute NoBareReturnKeyword.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoBareReturnKeyword.to_issue(@diagnostic).rule == :no_bare_return_keyword
  end

  test "issue message carries the diagnostic text" do
    assert NoBareReturnKeyword.to_issue(@diagnostic).message ==
             "undefined variable \"return\""
  end

  test "issue meta carries the line" do
    assert NoBareReturnKeyword.to_issue(@diagnostic).meta == %{line: 27}
  end
end
