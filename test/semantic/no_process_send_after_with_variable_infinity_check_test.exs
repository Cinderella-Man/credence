defmodule Credence.Semantic.NoProcessSendAfterWithVariableInfinityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoProcessSendAfterWithVariableInfinity

  @real_message "invalid args for &, expected one of:\n\n  * &Mod.fun/arity to capture a remote function, such as &Enum.map/2\n  * &fun/arity to capture a local or imported function, such as &is_atom/1\n  * &some_code(&1, ...) containing at least one argument as &1, such as &List.flatten(&1)\n\nGot: System.monotonic_time(:millisecond) / 0"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {10, 75}}
    assert NoProcessSendAfterWithVariableInfinity.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoProcessSendAfterWithVariableInfinity.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {10, 75}}

    assert NoProcessSendAfterWithVariableInfinity.to_issue(diag).rule ==
             :no_process_send_after_with_variable_infinity
  end
end
