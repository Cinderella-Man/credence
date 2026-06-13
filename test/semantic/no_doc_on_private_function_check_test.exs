defmodule Credence.Semantic.NoDocOnPrivateFunctionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDocOnPrivateFunction

  @doc_diag %{
    severity: :warning,
    message: "defp build_order_map/1 is private, @doc attribute is always discarded for private functions/macros/types",
    position: 18,
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
    assert NoDocOnPrivateFunction.match?(@doc_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoDocOnPrivateFunction.match?(diag)
  end

  test "does not match redefining module diagnostic" do
    refute NoDocOnPrivateFunction.match?(@redefining_diag)
  end

  test "attributes the issue to this rule" do
    assert NoDocOnPrivateFunction.to_issue(@doc_diag).rule == :no_doc_on_private_function
  end
end
