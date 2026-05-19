defmodule Credence.Semantic.UnusedVariableTest do
  use ExUnit.Case

  alias Credence.Semantic.UnusedVariable
  # ── Unit tests (rule logic with synthetic diagnostics) ──────────

  describe "match?/1" do
    test "matches unused variable warning" do
      diag = %{severity: :warning, message: ~s(variable "x" is unused), position: {5, 6}}
      assert UnusedVariable.match?(diag)
    end

    test "does not match unused function warning" do
      diag = %{severity: :warning, message: "function helper/1 is unused", position: {5, 6}}
      refute UnusedVariable.match?(diag)
    end

    test "does not match error severity" do
      diag = %{severity: :error, message: ~s(variable "x" is unused), position: {5, 6}}
      refute UnusedVariable.match?(diag)
    end

    test "does not match unrelated warning" do
      diag = %{severity: :warning, message: "some other warning", position: {5, 6}}
      refute UnusedVariable.match?(diag)
    end
  end

  describe "fix/2 (unit)" do
    test "prefixes unused variable with underscore" do
      source = """
      def run(list) do
        {current, max} = compute(list)
        max
      end
      """

      diag = %{
        severity: :warning,
        message: ~s(variable "current" is unused),
        position: {2, 4}
      }

      fixed = UnusedVariable.fix(source, diag)
      assert fixed =~ "_current"
      assert fixed =~ "max"
    end

    test "does not double-prefix already underscored variable" do
      source = """
      def run(list) do
        {_current, max} = compute(list)
        max
      end
      """

      diag = %{
        severity: :warning,
        message: ~s(variable "_current" is unused),
        position: {2, 4}
      }

      fixed = UnusedVariable.fix(source, diag)
      refute fixed =~ "__current"
    end

    test "fixes on correct line only" do
      source = """
      total = compute()
      {total, extra} = split(data)
      total
      """

      diag = %{
        severity: :warning,
        message: ~s(variable "extra" is unused),
        position: {2, 10}
      }

      fixed = UnusedVariable.fix(source, diag)
      # Only line 2 should be modified
      lines = String.split(fixed, "\n")
      assert Enum.at(lines, 1) =~ "_extra"
      # Line 1 and 3 untouched
      assert Enum.at(lines, 0) =~ "total = compute()"
      assert Enum.at(lines, 2) =~ "total"
    end

    test "handles position as bare integer" do
      source = "x = 1\n"

      diag = %{
        severity: :warning,
        message: ~s(variable "x" is unused),
        position: 1
      }

      fixed = UnusedVariable.fix(source, diag)
      assert fixed =~ "_x"
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{
        severity: :warning,
        message: ~s(variable "foo" is unused),
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

    test "fixes unused variable in tuple destructuring" do
      source = """
      defmodule UnusedVarInteg2 do
        def run do
          {current, max} = {1, 2}
          max
        end
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "_current"
      refute fixed =~ ~r/[^_]current/
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
end
