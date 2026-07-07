defmodule Credence.Semantic.FixNestedModuleShortReferenceCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixNestedModuleShortReference

  @real_diag %{
    severity: :warning,
    message:
      "redefining module WorkStealQueue (current version loaded from _build/test/lib/workspace/ebin/Elixir.WorkStealQueue.beam)",
    position: 1,
    file: "credence_check.ex",
    stacktrace: [{WorkStealQueue, :__MODULE__, 0, [file: "credence_check.ex", line: 1]}],
    source: "credence_check.ex",
    span: nil
  }

  test "matches the diagnostic" do
    assert FixNestedModuleShortReference.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixNestedModuleShortReference.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixNestedModuleShortReference.to_issue(@real_diag).rule ==
             :fix_nested_module_short_reference
  end
end
