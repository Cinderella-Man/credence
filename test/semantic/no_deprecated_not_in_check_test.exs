defmodule Credence.Semantic.NoDeprecatedNotInCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDeprecatedNotIn

  @real_message "\"not expr1 in expr2\" is deprecated, use \"expr1 not in expr2\" instead"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {81, 49}}
    assert NoDeprecatedNotIn.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoDeprecatedNotIn.match?(diag)
  end

  test "ignores a different warning about 'not in'" do
    diag = %{severity: :warning, message: "some other deprecation", position: {1, 1}}
    refute NoDeprecatedNotIn.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {81, 49}}
    assert NoDeprecatedNotIn.to_issue(diag).rule == :no_deprecated_not_in
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {81, 49}}
    assert NoDeprecatedNotIn.to_issue(diag).meta.line == 81
  end
end
