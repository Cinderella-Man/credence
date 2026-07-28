defmodule Credence.Semantic.FixJasonDecodeErrorMessageFieldCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixJasonDecodeErrorMessageField

  @real_message "unknown key :message for struct Jason.DecodeError"

  test "matches the diagnostic" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {148, 16},
      file: "credence_check.ex"
    }

    assert FixJasonDecodeErrorMessageField.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{
      severity: :error,
      message: "unrelated error",
      position: {1, 1},
      file: "credence_check.ex"
    }

    refute FixJasonDecodeErrorMessageField.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Factory (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixJasonDecodeErrorMessageField.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {148, 16},
      file: "credence_check.ex"
    }

    assert FixJasonDecodeErrorMessageField.to_issue(diag).rule ==
             :fix_jason_decode_error_message_field
  end

  test "sets the line in issue meta" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {42, 16},
      file: "credence_check.ex"
    }

    assert FixJasonDecodeErrorMessageField.to_issue(diag).meta.line == 42
  end
end
