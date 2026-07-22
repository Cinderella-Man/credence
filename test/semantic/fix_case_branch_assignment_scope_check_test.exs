defmodule Credence.Semantic.FixCaseBranchAssignmentScopeCheckTest do
  use ExUnit.Case, async: true

  alias Credence.Semantic.FixCaseBranchAssignmentScope

  @real_message "undefined variable \"label\""

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {9, 19}}
    assert FixCaseBranchAssignmentScope.match?(diag)
  end

  test "matches variables with ? and ! suffixes" do
    assert FixCaseBranchAssignmentScope.match?(%{
             severity: :error,
             message: "undefined variable \"valid?\"",
             position: {3, 5}
           })

    assert FixCaseBranchAssignmentScope.match?(%{
             severity: :error,
             message: "undefined variable \"save!\"",
             position: {3, 5}
           })
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute FixCaseBranchAssignmentScope.match?(diag)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: @real_message, position: {9, 19}}
    refute FixCaseBranchAssignmentScope.match?(diag)
  end

  test "ignores messages that merely embed the phrase" do
    diag = %{
      severity: :error,
      message: "mismatched delimiter found on line 3:\n  undefined variable \"x\" here",
      position: {3, 1}
    }

    refute FixCaseBranchAssignmentScope.match?(diag)
  end

  test "should_report? is true when the fix would rewrite the source" do
    source = ~S"""
    defmodule M do
      def classify(x) do
        case x do
          :ok -> label = "success"
          :error -> label = "failure"
          _ -> label = "unknown"
        end

        String.upcase(label)
      end
    end
    """

    diag = %{severity: :error, message: @real_message, position: {9, 19}}
    assert FixCaseBranchAssignmentScope.should_report?(diag, source)
  end

  test "should_report? is false for an undefined variable outside the case shape" do
    source = ~S"""
    defmodule FibStream do
      def stream do
        Stream.unfold({current, next}, fn {current, next} ->
          {current, {next, current + next}}
        end)
      end
    end
    """

    diag = %{severity: :error, message: "undefined variable \"current\"", position: {3, 19}}
    refute FixCaseBranchAssignmentScope.should_report?(diag, source)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {9, 17}}
    assert FixCaseBranchAssignmentScope.to_issue(diag).rule == :fix_case_branch_assignment_scope
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}}
    assert FixCaseBranchAssignmentScope.to_issue(diag).meta.line == 42
  end
end
