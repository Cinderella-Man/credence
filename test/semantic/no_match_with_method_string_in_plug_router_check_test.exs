defmodule Credence.Semantic.NoMatchWithMethodStringInPlugRouterCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoMatchWithMethodStringInPlugRouter

  @matching_msg "no function clause matching in Access.get/3"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @matching_msg, position: {1, 1}}
    assert NoMatchWithMethodStringInPlugRouter.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoMatchWithMethodStringInPlugRouter.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @matching_msg, position: {1, 1}}

    assert NoMatchWithMethodStringInPlugRouter.to_issue(diag).rule ==
             :no_match_with_method_string_in_plug_router
  end
end
