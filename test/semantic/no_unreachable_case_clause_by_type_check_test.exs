defmodule Credence.Semantic.NoUnreachableCaseClauseByTypeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnreachableCaseClauseByType

  @message "the following clause will never match:\n\n    :dt\n\nbecause it attempts to match on the result of:\n\n    DateTime.compare(due1, due2)\n\nwhich has type:\n\n    dynamic(:eq or :gt or :lt)\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @message, position: {220, 1}}
    assert NoUnreachableCaseClauseByType.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "ignores the exception-case diagnostic (handled by FixPinAtomInExceptionCase)" do
    msg =
      "the following clause will never match:\n\n    ^exception\n\nbecause it attempts to match on the result of:\n\n    e\n\nwhich has type:\n\n    %{..., __exception__: true, __struct__: atom()}\n"

    diag = %{severity: :warning, message: msg, position: {10, 1}}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @message, position: {220, 1}}

    assert NoUnreachableCaseClauseByType.to_issue(diag).rule ==
             :no_unreachable_case_clause_by_type
  end

  test "preserves the diagnostic message in the issue" do
    diag = %{severity: :warning, message: @message, position: {220, 1}}
    assert NoUnreachableCaseClauseByType.to_issue(diag).message == @message
  end
end
