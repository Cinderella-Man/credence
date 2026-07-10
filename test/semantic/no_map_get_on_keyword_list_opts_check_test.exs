defmodule Credence.Semantic.NoMapGetOnKeywordListOptsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoMapGetOnKeywordListOpts

  @match_msg "Map.get/2 called on keyword list opts"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {1, 1}}
    assert NoMapGetOnKeywordListOpts.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoMapGetOnKeywordListOpts.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {1, 1}}
    assert NoMapGetOnKeywordListOpts.to_issue(diag).rule == :no_map_get_on_keyword_list_opts
  end
end
