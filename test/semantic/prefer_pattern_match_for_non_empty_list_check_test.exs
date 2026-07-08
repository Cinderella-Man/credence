defmodule Credence.Semantic.PreferPatternMatchForNonEmptyListCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferPatternMatchForNonEmptyList

  @match_msg "do not use \"length(items) > 0\" to check if a list is not empty since length always traverses the whole list. Prefer to pattern match on a non-empty list, such as [_ | _], or use \"items != []\" as a guard"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {4, 32}}
    assert PreferPatternMatchForNonEmptyList.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferPatternMatchForNonEmptyList.match?(diag)
  end

  test "ignores diagnostics with different severity" do
    diag = %{severity: :error, message: @match_msg, position: {4, 32}}
    refute PreferPatternMatchForNonEmptyList.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {4, 32}}

    assert PreferPatternMatchForNonEmptyList.to_issue(diag).rule ==
             :prefer_pattern_match_for_non_empty_list
  end
end
