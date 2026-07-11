defmodule Credence.Semantic.NoMapUpdateZeroDefaultWithSubtractionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoMapUpdateZeroDefaultWithSubtraction

  @real_message "Map.update with zero default and subtraction in callback"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {8, 5}}
    assert NoMapUpdateZeroDefaultWithSubtraction.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoMapUpdateZeroDefaultWithSubtraction.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {8, 5}}

    assert NoMapUpdateZeroDefaultWithSubtraction.to_issue(diag).rule ==
             :no_map_update_zero_default_with_subtraction
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {8, 5}}
    assert NoMapUpdateZeroDefaultWithSubtraction.to_issue(diag).meta.line == 8
  end
end
