defmodule Credence.Semantic.NoMapHasCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoMapHas

  @matching_msg "Map.has?/2 is undefined or private"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @matching_msg, position: {1, 1}}
    assert NoMapHas.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoMapHas.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @matching_msg, position: {1, 1}}
    assert NoMapHas.to_issue(diag).rule == :no_map_has
  end
end
