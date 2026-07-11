defmodule Credence.Semantic.NoHallucinatedStructFieldInPatternCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedStructFieldInPattern

  test "matches the diagnostic" do
    diag = %{severity: :error, message: "key :size not found", position: {1, 1}}
    assert NoHallucinatedStructFieldInPattern.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedStructFieldInPattern.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: "key :size not found", position: {1, 1}}

    assert NoHallucinatedStructFieldInPattern.to_issue(diag).rule ==
             :no_hallucinated_struct_field_in_pattern
  end
end
