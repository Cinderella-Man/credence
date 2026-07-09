defmodule Credence.Semantic.FixInvalidCaptureWithArgumentsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixInvalidCaptureWithArguments

  @real_diag %{
    severity: :error,
    message: "undefined variable \"func\"",
    position: {148, 62}
  }

  test "matches the diagnostic" do
    assert FixInvalidCaptureWithArguments.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixInvalidCaptureWithArguments.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixInvalidCaptureWithArguments.to_issue(@real_diag).rule ==
             :fix_invalid_capture_with_arguments
  end
end
