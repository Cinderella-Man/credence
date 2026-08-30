defmodule Credence.Semantic.NoDuplicateDefstructCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDuplicateDefstruct

  @match_msg "defstruct has already been called for RetrySaga, defstruct can only be called once per module"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @match_msg, position: 0}
    assert NoDuplicateDefstruct.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoDuplicateDefstruct.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @match_msg, position: 0}
    assert NoDuplicateDefstruct.to_issue(diag).rule == :no_duplicate_defstruct
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @match_msg, position: {42, 5}}
    assert NoDuplicateDefstruct.to_issue(diag).meta.line == 42
  end
end
