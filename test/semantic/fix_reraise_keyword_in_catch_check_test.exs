defmodule Credence.Semantic.FixReraiseKeywordInCatchCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixReraiseKeywordInCatch

  @diagnostic %{
    severity: :error,
    message: "undefined variable \"reraise\"",
    position: {8, 9}
  }

  test "matches the diagnostic" do
    assert FixReraiseKeywordInCatch.match?(@diagnostic)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixReraiseKeywordInCatch.match?(diag)
  end

  test "ignores other undefined-variable diagnostics" do
    diag = %{severity: :error, message: "undefined variable \"label\"", position: {1, 1}}
    refute FixReraiseKeywordInCatch.match?(diag)
  end

  test "ignores warnings with matching message" do
    diag = %{severity: :warning, message: "undefined variable \"reraise\"", position: {1, 1}}
    refute FixReraiseKeywordInCatch.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixReraiseKeywordInCatch.to_issue(@diagnostic).rule == :fix_reraise_keyword_in_catch
  end

  test "issue message carries the diagnostic text" do
    assert FixReraiseKeywordInCatch.to_issue(@diagnostic).message ==
             "undefined variable \"reraise\""
  end

  test "issue meta carries the line" do
    assert FixReraiseKeywordInCatch.to_issue(@diagnostic).meta == %{line: 8}
  end

  test "wins dispatch over the generic undefined-variable rule" do
    # FixCaseBranchAssignmentScope claims every `undefined variable "name"`
    # diagnostic; dispatch is winner-take-all ordered by {priority, module}.
    # This rule must sort first or it is dead in production.
    assert FixReraiseKeywordInCatch.priority() <
             Credence.Semantic.FixCaseBranchAssignmentScope.priority()
  end

  test "should_report? is true when the fix rewrites the source" do
    source =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, reason ->
              reraise
          end
        end
      end
      """

    assert FixReraiseKeywordInCatch.should_report?(@diagnostic, source)
  end

  test "should_report? is false when the fix cannot rewrite the source" do
    source =
      """
      defmodule M do
        def f do
          try do
            :ok
          rescue
            e ->
              reraise
          end
        end
      end
      """

    refute FixReraiseKeywordInCatch.should_report?(@diagnostic, source)
  end
end
