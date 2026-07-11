defmodule Credence.Semantic.FixInvalidCaptureWithLiteralCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixInvalidCaptureWithLiteral

  @real_message "invalid args for &, expected one of:\n\n  * &Mod.fun/arity to capture a remote function, such as &Enum.map/2\n  * &fun/arity to capture a local or imported function, such as &is_atom/1\n  * &some_code(&1, ...) containing at least one argument as &1, such as &List.flatten(&1)\n\nGot: true"

  describe "match?/1" do
    test "matches the invalid-capture diagnostic" do
      diag = %{severity: :error, message: @real_message, position: {2, 43}}
      assert FixInvalidCaptureWithLiteral.match?(diag)
    end

    test "matches for different literals (false)" do
      msg = "invalid args for &, expected one of:\n\n  * ...\n\nGot: false"
      diag = %{severity: :error, message: msg, position: {2, 28}}
      assert FixInvalidCaptureWithLiteral.match?(diag)
    end

    test "matches for different literals (atom)" do
      msg = "invalid args for &, expected one of:\n\n  * ...\n\nGot: :atom"
      diag = %{severity: :error, message: msg, position: {2, 28}}
      assert FixInvalidCaptureWithLiteral.match?(diag)
    end

    test "ignores unrelated diagnostics" do
      diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
      refute FixInvalidCaptureWithLiteral.match?(diag)
    end

    test "ignores warnings even with matching message" do
      diag = %{severity: :warning, message: @real_message, position: {2, 43}}
      refute FixInvalidCaptureWithLiteral.match?(diag)
    end

    test "does not match generic compile errors" do
      diag = %{
        severity: :error,
        message: "cannot compile module (errors have been logged)",
        position: {1, 1}
      }

      refute FixInvalidCaptureWithLiteral.match?(diag)
    end

    test "does not fire on unused module attribute diagnostic" do
      diag = %{
        message: "module attribute @timestamp_size was set but never used",
        position: 8,
        file: "credence_check.ex",
        stacktrace: [{SecureToken, :__MODULE__, 0, [file: "credence_check.ex", line: 8]}],
        source: "credence_check.ex",
        span: nil,
        severity: :warning
      }

      refute FixInvalidCaptureWithLiteral.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "attributes the issue to this rule" do
      diag = %{severity: :error, message: @real_message, position: {2, 43}}
      assert FixInvalidCaptureWithLiteral.to_issue(diag).rule == :fix_invalid_capture_with_literal
    end

    test "preserves the diagnostic message" do
      diag = %{severity: :error, message: @real_message, position: {2, 43}}
      assert FixInvalidCaptureWithLiteral.to_issue(diag).message == @real_message
    end

    test "extracts line from {line, col} position" do
      diag = %{severity: :error, message: @real_message, position: {2, 43}}
      assert FixInvalidCaptureWithLiteral.to_issue(diag).meta.line == 2
    end

    test "handles bare integer position" do
      diag = %{severity: :error, message: @real_message, position: 5}
      assert FixInvalidCaptureWithLiteral.to_issue(diag).meta.line == 5
    end
  end
end
