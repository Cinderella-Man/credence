defmodule Credence.Semantic.FixNimbleCsvDirectParseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixNimbleCsvDirectParse

  @match_msg "NimbleCSV.parse_string/2 is undefined or private"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {7, 21}}
    assert FixNimbleCsvDirectParse.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixNimbleCsvDirectParse.match?(diag)
  end

  test "ignores NimbleCSV diagnostic without undefined or private" do
    diag = %{severity: :warning, message: "NimbleCSV.parse_string deprecated", position: {1, 1}}
    refute FixNimbleCsvDirectParse.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @match_msg, position: {7, 21}}
    refute FixNimbleCsvDirectParse.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {7, 21}}
    assert FixNimbleCsvDirectParse.to_issue(diag).rule == :fix_nimble_csv_direct_parse
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @match_msg, position: {42, 5}}
    assert FixNimbleCsvDirectParse.to_issue(diag).meta.line == 42
  end
end
