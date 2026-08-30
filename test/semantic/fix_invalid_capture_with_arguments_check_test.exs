defmodule Credence.Semantic.FixInvalidCaptureWithArgumentsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixInvalidCaptureWithArguments

  # Real diagnostic captured from Code.with_diagnostics on
  # `clock = &System.monotonic_time(:millisecond)/0` (line 3 of a module).
  @real_diag %{
    severity: :error,
    message:
      "invalid args for &, expected one of:\n\n" <>
        "  * &Mod.fun/arity to capture a remote function, such as &Enum.map/2\n" <>
        "  * &fun/arity to capture a local or imported function, such as &is_atom/1\n" <>
        "  * &some_code(&1, ...) containing at least one argument as &1, such as &List.flatten(&1)\n\n" <>
        "Got: System.monotonic_time(:millisecond) / 0",
    position: {3, 49}
  }

  test "matches the real invalid-capture diagnostic" do
    assert FixInvalidCaptureWithArguments.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixInvalidCaptureWithArguments.match?(diag)
  end

  test "ignores undefined-variable diagnostics (owned by other rules)" do
    diag = %{severity: :error, message: "undefined variable \"func\"", position: {1, 1}}
    refute FixInvalidCaptureWithArguments.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixInvalidCaptureWithArguments.to_issue(@real_diag).rule ==
             :fix_invalid_capture_with_arguments
  end

  test "should_report? is true only when the fix would rewrite the source" do
    fixable = """
    defmodule Example do
      def start do
        clock = &System.monotonic_time(:millisecond)/0
        clock.()
      end
    end
    """

    # Same diagnostic message, but the source's capture declares arity 1 —
    # a shape the fix deliberately skips.
    skipped = """
    defmodule Example do
      def go(list, x) do
        Enum.map(list, &transform(x)/1)
      end
    end
    """

    assert FixInvalidCaptureWithArguments.should_report?(@real_diag, fixable)
    refute FixInvalidCaptureWithArguments.should_report?(@real_diag, skipped)
  end
end
