defmodule Credence.Semantic.NoUndefinedGuardEqualityInCaseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUndefinedGuardEqualityInCase

  # The real diagnostic Elixir emits when LLM writes `:ets:info` (colon syntax).
  @real_message "invalid syntax found on credence_check.ex:81:18:\n    error: syntax error before: info\n    │\n 81 │         case :ets:info(:feature_flags) do\n    │                  ^\n    │\n    └─ credence_check.ex:81:18"

  describe "match?/1" do
    test "matches the real diagnostic" do
      diag = %{severity: :error, message: @real_message, position: 81, file: "credence_check.ex"}
      assert NoUndefinedGuardEqualityInCase.match?(diag)
    end

    test "ignores unrelated diagnostics" do
      diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
      refute NoUndefinedGuardEqualityInCase.match?(diag)
    end

    test "ignores warnings with the same message" do
      diag = %{severity: :warning, message: @real_message, position: 81}
      refute NoUndefinedGuardEqualityInCase.match?(diag)
    end

    test "ignores generic compile error wrapper" do
      diag = %{
        severity: :error,
        message: "credence_check.ex: cannot compile module (errors have been logged)",
        position: 0,
        file: "credence_check.ex"
      }

      refute NoUndefinedGuardEqualityInCase.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "attributes the issue to this rule" do
      diag = %{severity: :error, message: @real_message, position: 81, file: "credence_check.ex"}
      assert NoUndefinedGuardEqualityInCase.to_issue(diag).rule ==
               :no_undefined_guard_equality_in_case
    end

    test "sets the line in issue meta" do
      diag = %{severity: :error, message: @real_message, position: {42, 10}, file: "credence_check.ex"}
      assert NoUndefinedGuardEqualityInCase.to_issue(diag).meta.line == 42
    end

    test "handles bare integer position" do
      diag = %{severity: :error, message: @real_message, position: 81}
      assert NoUndefinedGuardEqualityInCase.to_issue(diag).meta.line == 81
    end
  end
end
