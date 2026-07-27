defmodule Credence.Semantic.NoHallucinatedEtsKeytypeOptionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedEtsKeytypeOption

  @real_message "errors were found at the given arguments:\n\n  * 2nd argument: invalid options\n"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {3, 5}}
    assert NoHallucinatedEtsKeytypeOption.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoHallucinatedEtsKeytypeOption.match?(diag)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: @real_message, position: {1, 1}}
    refute NoHallucinatedEtsKeytypeOption.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {3, 5}}

    assert NoHallucinatedEtsKeytypeOption.to_issue(diag).rule ==
             :no_hallucinated_ets_keytype_option
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 10}}
    assert NoHallucinatedEtsKeytypeOption.to_issue(diag).meta.line == 42
  end
end
