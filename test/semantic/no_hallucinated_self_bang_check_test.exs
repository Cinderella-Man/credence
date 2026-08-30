defmodule Credence.Semantic.NoHallucinatedSelfBangCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedSelfBang

  @real_message "undefined function self!/1 (expected CancellablePriorityQueue to define such a function or for it to be imported, but none are available)"
  @real_diag %{
    severity: :error,
    message: @real_message,
    position: {75, 7},
    file: "credence_check.ex",
    stacktrace: [
      {CancellablePriorityQueue, :handle_call, 3,
       [file: "credence_check.ex", column: 7, line: 75]}
    ],
    source: "credence_check.ex",
    span: {75, 12}
  }

  test "matches the diagnostic" do
    assert NoHallucinatedSelfBang.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}}
    refute NoHallucinatedSelfBang.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message:
        "credence_check.ex: cannot compile module CancellablePriorityQueue (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedSelfBang.match?(diag)
  end

  test "ignores undefined function for other names" do
    diag = %{
      severity: :error,
      message:
        "undefined function self!/2 (expected M to define such a function or for it to be imported, but none are available)",
      position: {3, 5}
    }

    refute NoHallucinatedSelfBang.match?(diag)
  end

  test "ignores higher arities whose message contains self!/1 as a substring" do
    diag = %{
      severity: :error,
      message:
        "undefined function self!/12 (expected M to define such a function or for it to be imported, but none are available)",
      position: {3, 5}
    }

    refute NoHallucinatedSelfBang.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoHallucinatedSelfBang.to_issue(@real_diag).rule == :no_hallucinated_self_bang
  end

  test "sets the line in issue meta" do
    assert NoHallucinatedSelfBang.to_issue(@real_diag).meta.line == 75
  end
end
