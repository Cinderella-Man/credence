defmodule Credence.Semantic.NoRescueInExceptionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoRescueInException

  @real_message "struct Exception is undefined (there is such module but it does not define a struct)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {145, 9}}
    assert NoRescueInException.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoRescueInException.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {145, 9}}
    assert NoRescueInException.to_issue(diag).rule == :no_rescue_in_exception
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {145, 9}}
    assert NoRescueInException.to_issue(diag).meta.line == 145
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {145, 9}}
    refute NoRescueInException.match?(diag)
  end
end
