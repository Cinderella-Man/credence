defmodule Credence.Semantic.FixKeywordDoubleColonCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixKeywordDoubleColon

  @message "misplaced operator ::/2"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @message, position: {5, 47}}
    assert FixKeywordDoubleColon.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixKeywordDoubleColon.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @message, position: {5, 47}}
    assert FixKeywordDoubleColon.to_issue(diag).rule == :fix_keyword_double_colon
  end
end
