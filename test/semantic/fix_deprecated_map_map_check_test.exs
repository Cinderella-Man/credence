defmodule Credence.Semantic.FixDeprecatedMapMapCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixDeprecatedMapMap

  @message "Map.map/2 is deprecated. Use Map.new/2 instead."

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @message, position: {3, 5}}
    assert FixDeprecatedMapMap.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated warning", position: {1, 1}}
    refute FixDeprecatedMapMap.match?(diag)
  end

  test "ignores non-deprecated Map.map messages" do
    diag = %{severity: :warning, message: "undefined function Map.map/2", position: {1, 1}}
    refute FixDeprecatedMapMap.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @message, position: {3, 5}}
    issue = FixDeprecatedMapMap.to_issue(diag)
    assert issue.rule == :fix_deprecated_map_map
    assert issue.meta.line == 3
  end
end
