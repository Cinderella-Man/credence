defmodule Credence.Semantic.FixLocalFunctionInGuardCheckTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Semantic.FixLocalFunctionInGuard

  @real_message "cannot find or invoke local is_range/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: is_range(length_range)"

  test "matches the diagnostic" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {93, 47},
      file: "credence_check.ex"
    }

    assert FixLocalFunctionInGuard.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute FixLocalFunctionInGuard.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixLocalFunctionInGuard.match?(diag)
  end

  # This test used to `refute` the match — pinning the defect rather than the
  # contract. The matcher was hardcoded to the literal string
  # `"cannot find or invoke local is_range/1 inside a guard"`, so `is_blank/1`,
  # `table/0` and `__match_pattern__/2` produced `no rule matched diagnostic`
  # on real rows (escalation ledger 115/145/192). The rule's NAME promised a
  # general repair its matcher never attempted.
  #
  # The contract now: it MATCHES any local-in-guard error, and declines through
  # `should_report?/2` when it cannot inline safely.
  test "matches any local function in guard error, not just is_range/1" do
    diag = %{
      severity: :error,
      message:
        "cannot find or invoke local is_foo/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: is_foo(x)",
      position: {2, 33}
    }

    assert FixLocalFunctionInGuard.match?(diag)
  end

  test "declines to report when the helper cannot be inlined into a guard" do
    # `String.trim/1` is not allowed in a guard, so inlining this body would
    # swap one compile error for another. Matching without reporting is the
    # point: it must not claim the diagnostic it cannot repair.
    source = """
    defmodule Blank do
      defp is_blank(l), do: byte_size(String.trim(l)) == 0
      def f(line) when is_blank(line), do: :ok
    end
    """

    diag = %{
      severity: :error,
      message:
        "cannot find or invoke local is_blank/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: is_blank(line)",
      position: {3, 20}
    }

    assert FixLocalFunctionInGuard.match?(diag)
    refute FixLocalFunctionInGuard.should_report?(diag, source)
  end

  test "reports and repairs a fixable local function call in a guard end to end" do
    source = """
    defmodule LocalFnInGuardCheckPositive do
      defp is_even(x), do: rem(x, 2) == 0
      def classify(x) when is_even(x), do: :even
    end
    """

    expected = """
    defmodule LocalFnInGuardCheckPositive do
      defp is_even(x), do: rem(x, 2) == 0
      def classify(x) when rem(x, 2) == 0, do: :even
    end
    """

    assert {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(source)

    diagnostic = Enum.find(diagnostics, &FixLocalFunctionInGuard.match?/1)
    assert diagnostic
    assert FixLocalFunctionInGuard.should_report?(diagnostic, source)

    assert [issue] = Credence.Semantic.analyze(source)
    assert issue.rule == :fix_local_function_in_guard

    fixed = Credence.Semantic.fix(source)
    confirm_fix(fixed, expected)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {93, 47},
      file: "credence_check.ex"
    }

    assert FixLocalFunctionInGuard.to_issue(diag).rule == :fix_local_function_in_guard
  end

  test "sets the line in issue meta" do
    diag = %{
      severity: :error,
      message: @real_message,
      position: {42, 10},
      file: "credence_check.ex"
    }

    assert FixLocalFunctionInGuard.to_issue(diag).meta.line == 42
  end
end
