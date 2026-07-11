defmodule Credence.Semantic.FixEtsNewStringNameCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixEtsNewStringName

  @real_message "string interpolation passed as table name to :ets.new/2 — use atom interpolation (:\"...\") instead"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 21}}
    assert FixEtsNewStringName.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixEtsNewStringName.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute FixEtsNewStringName.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 21}}
    assert FixEtsNewStringName.to_issue(diag).rule == :fix_ets_new_string_name
  end

  test "preserves the diagnostic message" do
    diag = %{severity: :warning, message: @real_message, position: {3, 21}}
    assert FixEtsNewStringName.to_issue(diag).message == @real_message
  end

  test "extracts line from tuple position" do
    diag = %{severity: :warning, message: @real_message, position: {5, 12}}
    assert FixEtsNewStringName.to_issue(diag).meta.line == 5
  end
end
