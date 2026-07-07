defmodule Credence.Semantic.PreferRescueBeforeCatchCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferRescueBeforeCatch

  @diagnostic %{
    severity: :warning,
    message: "\"catch\" should always come after \"rescue\" in try",
    position: {4, 7}
  }

  test "matches the diagnostic" do
    assert PreferRescueBeforeCatch.match?(@diagnostic)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferRescueBeforeCatch.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert PreferRescueBeforeCatch.to_issue(@diagnostic).rule == :prefer_rescue_before_catch
  end
end
