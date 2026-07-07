defmodule Credence.Semantic.NoMapUpdateMissingKeyCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoMapUpdateMissingKey

  @real_message "expected a map with key :timer_ref in map update syntax:\n\n    %{state | timer_ref: timer_ref}\n\nbut got type:\n\n    dynamic(%{\n      cleanup_interval_ms: term(),\n      clock: term(),\n      idempotency: empty_map(),\n      next_id: integer(),\n      payments: empty_map(),\n      processor: term(),\n      ttl_ms: term()\n    })\n\nwhere \"state\" was given the type:\n\n    # type: dynamic(%{\n      cleanup_interval_ms: term(),\n      clock: term(),\n      idempotency: empty_map(),\n      next_id: integer(),\n      payments: empty_map(),\n      processor: term(),\n      ttl_ms: term()\n    })\n    # from: credence_check.ex:40:11\n    state = %{\n      payments: %{},\n      idempotency: %{},\n      next_id: 1,\n      clock: clock,\n      ttl_ms: ttl_ms,\n      cleanup_interval_ms: cleanup_interval_ms,\n      processor: processor\n    }\n\nwhere \"timer_ref\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:34:15\n    timer_ref =\n      case cleanup_interval_ms do\n        :infinity -> nil\n        _ -> Process.send_after(self(), :cleanup, cleanup_interval_ms)\n      end\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {50, 11}, file: "credence_check.ex"}
    assert NoMapUpdateMissingKey.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}, file: "credence_check.ex"}
    refute NoMapUpdateMissingKey.match?(diag)
  end

  test "ignores generic compile warning wrapper" do
    diag = %{
      severity: :warning,
      message: "credence_check.ex: cannot compile module (warnings have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoMapUpdateMissingKey.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {50, 11}, file: "credence_check.ex"}
    assert NoMapUpdateMissingKey.to_issue(diag).rule == :no_map_update_missing_key
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {50, 11}, file: "credence_check.ex"}
    assert NoMapUpdateMissingKey.to_issue(diag).meta.line == 50
  end

  test "issue message mentions the missing key" do
    diag = %{severity: :warning, message: @real_message, position: {50, 11}, file: "credence_check.ex"}
    assert NoMapUpdateMissingKey.to_issue(diag).message =~ ":timer_ref"
  end
end
