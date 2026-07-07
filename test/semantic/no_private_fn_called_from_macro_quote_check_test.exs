defmodule Credence.Semantic.NoPrivateFnCalledFromMacroQuoteCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoPrivateFnCalledFromMacroQuote

  # The real captured diagnostic from Code.with_diagnostics when a defp
  # function is called only from within a macro's quote block.
  @real_diag %{
    message: "function check_monotonic/4 is unused",
    position: {69, 8},
    file: "credence_check.ex",
    stacktrace: [{AssertHelpers, :__MODULE__, 0, [file: "credence_check.ex", column: 8, line: 69]}],
    source: "credence_check.ex",
    span: nil,
    severity: :warning
  }

  test "matches the diagnostic" do
    assert NoPrivateFnCalledFromMacroQuote.match?(@real_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unused variable x", position: {1, 1}}
    refute NoPrivateFnCalledFromMacroQuote.match?(diag)
  end

  test "does not match non-warning severity" do
    diag = %{severity: :error, message: "function check_monotonic/4 is unused", position: {69, 8}}
    refute NoPrivateFnCalledFromMacroQuote.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoPrivateFnCalledFromMacroQuote.to_issue(@real_diag).rule ==
             :no_private_fn_called_from_macro_quote
  end

  test "preserves the diagnostic message in the issue" do
    assert NoPrivateFnCalledFromMacroQuote.to_issue(@real_diag).message ==
             "function check_monotonic/4 is unused"
  end

  test "sets the line in issue meta" do
    assert NoPrivateFnCalledFromMacroQuote.to_issue(@real_diag).meta.line == 69
  end
end
