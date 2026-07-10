defmodule Credence.Semantic.NoProcessSendAfterLiteralInfinityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoProcessSendAfterLiteralInfinity

  @real_message "variable acc in code block has no effect as it is never returned (remove the variable or assign it to _ to avoid warnings)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {204, 11}}
    assert NoProcessSendAfterLiteralInfinity.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoProcessSendAfterLiteralInfinity.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {204, 11}}

    assert NoProcessSendAfterLiteralInfinity.to_issue(diag).rule ==
             :no_process_send_after_literal_infinity
  end
end
