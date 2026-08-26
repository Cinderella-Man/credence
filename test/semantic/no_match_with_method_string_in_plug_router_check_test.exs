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

  test "does not report an Access.get/3 failure when the source has no router match to repair" do
    diag = %{severity: :error, message: @matching_msg, position: {1, 1}}
    source = ~S'Access.get("not a keyword", :key, :default)'

    refute NoMatchWithMethodStringInPlugRouter.should_report?(diag, source)
  end

  test "reports the diagnostic when its line identifies a method-string match in a Plug.Router" do
    source = """
    defmodule ReportableRouterNMWMSIPR do
      use Plug.Router
      match "POST", "/events" do
        send_resp(conn, 200, "ok")
      end
    end
    """

    diag = %{severity: :error, message: @matching_msg, position: {3, 1}}

    assert NoMatchWithMethodStringInPlugRouter.should_report?(diag, source)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @matching_msg, position: {1, 1}}

    assert NoMatchWithMethodStringInPlugRouter.to_issue(diag).rule ==
             :no_match_with_method_string_in_plug_router
  end
end
