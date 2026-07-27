defmodule Credence.Semantic.NoProcessSendAfterInfinityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoProcessSendAfterInfinity

  @real_message "def start_link/1 has multiple clauses and also declares default values. In such cases, the default values should be defined in a header. Instead of:\n\n    def foo(:first_clause, b \\\\ :default) do ... end\n    def foo(:second_clause, b) do ... end\n\none should write:\n\n    def foo(a, b \\\\ :default)\n    def foo(:first_clause, b) do ... end\n    def foo(:second_clause, b) do ... end\n\nthe previous clause is defined on line 5\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    assert NoProcessSendAfterInfinity.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoProcessSendAfterInfinity.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    assert NoProcessSendAfterInfinity.to_issue(diag).rule == :no_process_send_after_infinity
  end
end
