defmodule Credence.Semantic.NoHallucinatedDefpstructCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedDefpstruct

  @real_message "undefined function defpstruct/2 (there is no such import)"

  # The three other real spellings. `defpstructp/1` is the one from escalation
  # ledger row 183: the matcher used to be the literal `"undefined function
  # defpstruct/"`, and the character after `defpstruct` here is `p`, not `/`,
  # so the catch-all `UndefinedFunction` took the slot and no-opped.
  @real_message_p2 "undefined function defpstructp/2 (there is no such import)"
  @real_message_kw "undefined function defpstruct/1 (there is no such import)"
  @real_message_p_kw "undefined function defpstructp/1 (there is no such import)"

  test "matches the defpstructp block spelling (ledger row 183)" do
    diag = %{severity: :error, message: @real_message_p2, position: {2, 3}}
    assert NoHallucinatedDefpstruct.match?(diag)
  end

  test "matches the keyword form of both spellings" do
    for msg <- [@real_message_kw, @real_message_p_kw] do
      assert NoHallucinatedDefpstruct.match?(%{severity: :error, message: msg, position: {2, 3}})
    end
  end

  test "does not match a different macro that merely starts the same way" do
    diag = %{
      severity: :error,
      message: "undefined function defpstructx/1 (there is no such import)",
      position: {2, 3}
    }

    refute NoHallucinatedDefpstruct.match?(diag)
  end

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
