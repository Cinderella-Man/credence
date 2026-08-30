defmodule Credence.Semantic.UnusedVariableCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.UnusedVariable

  # ── Unit tests (rule logic with synthetic diagnostics) ──────────

  describe "match?/1" do
    test "matches unused variable warning" do
      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: {5, 6}
      }

      assert UnusedVariable.match?(diag)
    end

    test "does not match unused function warning" do
      diag = %{severity: :warning, message: "function helper/1 is unused", position: {5, 6}}
      refute UnusedVariable.match?(diag)
    end

    test "does not match error severity" do
      diag = %{
        severity: :error,
        message: """
        variable "x" is unused
        """,
        position: {5, 6}
      }

      refute UnusedVariable.match?(diag)
    end

    test "does not match unrelated warning" do
      diag = %{severity: :warning, message: "some other warning", position: {5, 6}}
      refute UnusedVariable.match?(diag)
    end

    # Deliberately NOT handled — see the moduledoc. The compiler offers two
    # repairs for this warning and only one of them ("remove the leading
    # underscore") preserves the answer; renaming to `_ref_1` would turn
    # `{_ref, _ref}` — which matches only equal pairs — into a pattern that
    # matches anything. `check` therefore stays silent, so it cannot disagree
    # with `fix`.
    test "does NOT match 'the underscored variable appears more than once' warning" do
      diag = %{
        severity: :warning,
        message:
          "the underscored variable \"_ref\" appears more than once in a match. " <>
            "This means the pattern will only match if all \"_ref\" bind to the same value. " <>
            "If this is the intended behaviour, please remove the leading underscore from the " <>
            "variable name, otherwise give the variables different names",
        position: {2, 16}
      }

      refute UnusedVariable.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{
        severity: :warning,
        message: """
        variable "foo" is unused
        """,
        position: {7, 4}
      }

      issue = UnusedVariable.to_issue(diag)
      assert issue.rule == :unused_variable
      assert issue.meta.line == 7
      assert issue.message =~ "foo"
    end
  end

  # ── Integration tests (through Credence.Semantic coordinator) ───

  describe "integration through Credence.Semantic" do
    test "detects unused variable in tuple destructuring" do
      source = """
      defmodule UnusedVarInteg1 do
        def run do
          {current, max} = {1, 2}
          max
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      unused = Enum.filter(issues, &(&1.rule == :unused_variable))
      assert length(unused) == 1
      assert hd(unused).message =~ "current"
    end

    test "no issues when all variables are used" do
      source = """
      defmodule UnusedVarInteg3 do
        def run(a, b) do
          a + b
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      unused = Enum.filter(issues, &(&1.rule == :unused_variable))
      assert unused == []
    end

    test "no issues when variable already prefixed with underscore" do
      source = """
      defmodule UnusedVarInteg4 do
        def run do
          {_current, max} = {1, 2}
          max
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      unused = Enum.filter(issues, &(&1.rule == :unused_variable))
      assert unused == []
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Negative cases: nothing to fix because the compiler emits no warning.
  # ════════════════════════════════════════════════════════════════

  describe "should NOT trigger" do
    test "variable used in the body — no warning" do
      source = """
      defmodule Used do
        def f(x), do: x
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end

    test "variable used only in a guard — no warning" do
      source = """
      defmodule UsedGuard do
        def f(x) when is_atom(x), do: :ok
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end

    test "bare `_` placeholder — no warning" do
      source = """
      defmodule BareU do
        def f(_, b), do: b
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end

    test "intentional pattern-match equality (`x, x`) is not flagged" do
      source = """
      defmodule Eq do
        def f(x, x), do: x
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end

    # The real compiler emits "the underscored variable ... appears more than
    # once in a match" here. The rule stays out of it — see match?/1 above.
    test "repeated underscored variable in a pattern is not flagged" do
      source = """
      defmodule RepeatedUnderscore do
        def f({_ref, _ref}), do: :ok
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end
  end
end
