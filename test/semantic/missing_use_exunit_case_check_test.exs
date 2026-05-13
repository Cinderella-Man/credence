defmodule Credence.Semantic.MissingUseExUnitCaseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.MissingUseExUnitCase

  # ═══════════════════════════════════════════════════════════════════
  # match?/1 — diagnostic matching
  # ═══════════════════════════════════════════════════════════════════

  describe "match?/1 returns true for ExUnit-related compile errors" do
    test "undefined function describe/2" do
      diagnostic = %{
        severity: :error,
        message: "undefined function describe/2 (there is no such import)",
        position: {13, 3}
      }

      assert MissingUseExUnitCase.match?(diagnostic)
    end

    test "undefined function test/2" do
      diagnostic = %{
        severity: :error,
        message: "undefined function test/2 (there is no such import)",
        position: 5
      }

      assert MissingUseExUnitCase.match?(diagnostic)
    end

    test "undefined function test/3 (with context)" do
      diagnostic = %{
        severity: :error,
        message: "undefined function test/3 (there is no such import)",
        position: 7
      }

      assert MissingUseExUnitCase.match?(diagnostic)
    end

    test "undefined function setup/1" do
      diagnostic = %{
        severity: :error,
        message: "undefined function setup/1 (there is no such import)",
        position: 3
      }

      assert MissingUseExUnitCase.match?(diagnostic)
    end
  end

  describe "match?/1 returns false for unrelated diagnostics" do
    test "other undefined function error" do
      diagnostic = %{
        severity: :error,
        message: "undefined function foo/2 (there is no such import)",
        position: 5
      }

      refute MissingUseExUnitCase.match?(diagnostic)
    end

    test "warning-level diagnostic even with matching message" do
      diagnostic = %{
        severity: :warning,
        message: "undefined function test/2 (there is no such import)",
        position: 5
      }

      refute MissingUseExUnitCase.match?(diagnostic)
    end

    test "unrelated compile error" do
      diagnostic = %{
        severity: :error,
        message: "undefined variable x",
        position: 10
      }

      refute MissingUseExUnitCase.match?(diagnostic)
    end

    test "nil diagnostic" do
      refute MissingUseExUnitCase.match?(nil)
    end

    test "empty map" do
      refute MissingUseExUnitCase.match?(%{})
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # to_issue/1 — issue generation
  # ═══════════════════════════════════════════════════════════════════

  describe "to_issue/1" do
    test "builds issue from diagnostic with line number" do
      diagnostic = %{
        severity: :error,
        message: "undefined function describe/2 (there is no such import)",
        position: 13
      }

      issue = MissingUseExUnitCase.to_issue(diagnostic)
      assert issue.rule == :missing_use_exunit_case
      assert issue.meta.line == 13
    end

    test "handles {line, column} position tuple" do
      diagnostic = %{
        severity: :error,
        message: "undefined function test/2 (there is no such import)",
        position: {7, 3}
      }

      issue = MissingUseExUnitCase.to_issue(diagnostic)
      assert issue.meta.line == 7
    end
  end
end
