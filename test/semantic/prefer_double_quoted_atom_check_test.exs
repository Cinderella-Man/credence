defmodule Credence.Semantic.PreferDoubleQuotedAtomCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferDoubleQuotedAtom

  @real_message "using single-quoted strings to represent charlists is deprecated.\nUse ~c\"\" if you indeed want a charlist or use \"\" instead.\nYou may run \"mix format --migrate\" to change all single-quoted\nstrings to use the ~c sigil and fix this warning."

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {119, 7}}
    assert PreferDoubleQuotedAtom.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferDoubleQuotedAtom.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {119, 7}}
    assert PreferDoubleQuotedAtom.to_issue(diag).rule == :prefer_double_quoted_atom
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {119, 7}}
    assert PreferDoubleQuotedAtom.to_issue(diag).meta.line == 119
  end
end
