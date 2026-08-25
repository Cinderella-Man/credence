defmodule Credence.Semantic.FixNegatedCaptureWithArityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixInvalidCaptureWithArguments
  alias Credence.Semantic.FixNegatedCaptureWithArity

  # Shared body of the real `invalid args for &` message, captured from
  # Code.with_diagnostics; only the trailing `Got:` line varies per shape.
  @message_body "invalid args for &, expected one of:\n\n" <>
                  "  * &Mod.fun/arity to capture a remote function, such as &Enum.map/2\n" <>
                  "  * &fun/arity to capture a local or imported function, such as &is_atom/1\n" <>
                  "  * &some_code(&1, ...) containing at least one argument as &1, such as &List.flatten(&1)\n\n"

  # Real diagnostics: `f = &(!String.contains?/2)` and the module-context
  # variants of `&(not Enum.empty?/1)`, `&(!local_fun/1)`, `&(not local_fun/1)`.
  @bang_remote %{
    severity: :error,
    message: @message_body <> "Got: !String.contains?() / 2",
    position: {1, 24}
  }
  @not_remote %{
    severity: :error,
    message: @message_body <> "Got: not Enum.empty?() / 1",
    position: {2, 54}
  }
  @bang_local %{
    severity: :error,
    message: @message_body <> "Got: !local_fun / 1",
    position: {2, 51}
  }
  @not_local %{
    severity: :error,
    message: @message_body <> "Got: not local_fun / 1",
    position: {2, 54}
  }

  # Real diagnostic for `&System.monotonic_time(:millisecond)/0` — the
  # non-negated shape owned by FixInvalidCaptureWithArguments.
  @non_negated %{
    severity: :error,
    message: @message_body <> "Got: System.monotonic_time(:millisecond) / 0",
    position: {3, 49}
  }

  test "matches negated-capture diagnostics (!, not, remote, local)" do
    assert FixNegatedCaptureWithArity.match?(@bang_remote)
    assert FixNegatedCaptureWithArity.match?(@not_remote)
    assert FixNegatedCaptureWithArity.match?(@bang_local)
    assert FixNegatedCaptureWithArity.match?(@not_local)
  end

  test "ignores non-negated invalid-capture diagnostics (owned by FixInvalidCaptureWithArguments)" do
    refute FixNegatedCaptureWithArity.match?(@non_negated)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "undefined variable \"func\"", position: {1, 1}}
    refute FixNegatedCaptureWithArity.match?(diag)
  end

  test "ignores warnings" do
    refute FixNegatedCaptureWithArity.match?(%{@bang_remote | severity: :warning})
  end

  test "sorts before FixInvalidCaptureWithArguments, whose broader match? would shadow it" do
    assert FixNegatedCaptureWithArity.priority() < FixInvalidCaptureWithArguments.priority()
  end

  test "attributes the issue to this rule" do
    issue = FixNegatedCaptureWithArity.to_issue(@bang_remote)
    assert issue.rule == :fix_negated_capture_with_arity
    assert issue.meta.line == 1
  end

  test "should_report? is true only when the fix would rewrite the source" do
    fixable = """
    defmodule Example do
      def any_full?(lists) do
        Enum.any?(lists, &(!Enum.empty?/1))
      end
    end
    """

    # Same diagnostic family, but a /0 arity — a shape the fix deliberately
    # skips (a capture must take at least one argument).
    skipped = """
    defmodule Example do
      def check do
        Enum.map([1], &(!zero_arity_fun/0))
      end
    end
    """

    diagnostic = %{@bang_remote | position: 3}
    assert FixNegatedCaptureWithArity.should_report?(diagnostic, fixable)
    refute FixNegatedCaptureWithArity.should_report?(diagnostic, skipped)
  end
end
