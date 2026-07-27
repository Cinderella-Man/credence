defmodule Credence.Semantic.NoHallucinatedDefpstructCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedDefpstruct

  @real_message "undefined function defpstruct/2 (there is no such import)"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {2, 3}}
    assert NoHallucinatedDefpstruct.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoHallucinatedDefpstruct.match?(diag)
  end

  test "ignores warning severity" do
    diag = %{severity: :warning, message: @real_message, position: {2, 3}}
    refute NoHallucinatedDefpstruct.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {2, 3}}
    assert NoHallucinatedDefpstruct.to_issue(diag).rule == :no_hallucinated_defpstruct
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}}
    assert NoHallucinatedDefpstruct.to_issue(diag).meta.line == 42
  end
end
