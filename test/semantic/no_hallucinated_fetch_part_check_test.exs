defmodule Credence.Semantic.NoHallucinatedFetchPartCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedFetchPart

  @real_message "function init/1 required by behaviour Plug was implemented as \"defp\" but should have been \"def\" (in module FileUpload.Router)"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    assert NoHallucinatedFetchPart.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedFetchPart.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    assert NoHallucinatedFetchPart.to_issue(diag).rule == :no_hallucinated_fetch_part
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 5}}
    assert NoHallucinatedFetchPart.to_issue(diag).meta.line == 42
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute NoHallucinatedFetchPart.match?(diag)
  end
end
