defmodule Credence.Semantic.NoBareDocAttributeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoBareDocAttribute

  # The real captured diagnostic from Code.with_diagnostics when compiling
  # source with a bare `@doc` (no arguments) before `def`.
  @bare_doc_diag %{
    severity: :warning,
    message: "module attribute @doc in code block has no effect",
    position: {2, 3},
    file: "credence_check.ex",
    source: "credence_check.ex"
  }

  # The real captured diagnostic from Code.with_diagnostics when compiling
  # source that redefines an already-loaded module. This is a must-not-fire
  # case — the rule should NOT match this diagnostic.
  @redefining_diag %{
    message:
      "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)",
    position: 1,
    file: "credence_check.ex",
    stacktrace: [{Solution, :__MODULE__, 0, [file: "credence_check.ex", line: 1]}],
    source: "credence_check.ex",
    span: nil,
    severity: :warning
  }

  test "matches the diagnostic" do
    assert NoBareDocAttribute.match?(@bare_doc_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoBareDocAttribute.match?(diag)
  end

  test "does not match redefining module diagnostic" do
    refute NoBareDocAttribute.match?(@redefining_diag)
  end

  test "attributes the issue to this rule" do
    assert NoBareDocAttribute.to_issue(@bare_doc_diag).rule == :no_bare_doc_attribute
  end
end
