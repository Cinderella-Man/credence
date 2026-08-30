defmodule Credence.Semantic.NoImplTrueForUndeclaredCallbackCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoImplTrueForUndeclaredCallback

  @real_message "got \"@impl true\" for function handle_call/3 but no behaviour specifies such callback. The known callbacks are:\n\n  * Supervisor.init/1 (function)\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {10, 1}}
    assert NoImplTrueForUndeclaredCallback.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoImplTrueForUndeclaredCallback.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {10, 1}}
    refute NoImplTrueForUndeclaredCallback.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {10, 1}}

    assert NoImplTrueForUndeclaredCallback.to_issue(diag).rule ==
             :no_impl_true_for_undeclared_callback
  end

  test "extracts the function name and arity in the issue message" do
    diag = %{severity: :warning, message: @real_message, position: {10, 1}}

    assert NoImplTrueForUndeclaredCallback.to_issue(diag).message ==
             "@impl true for handle_call/3 but no behaviour specifies such callback"
  end

  test "extracts a punctuated function name accepted by match?/1" do
    message =
      "got \"@impl true\" for function valid?/1 but no behaviour specifies such callback"

    diag = %{severity: :warning, message: message, position: {3, 1}}

    assert NoImplTrueForUndeclaredCallback.match?(diag)

    assert NoImplTrueForUndeclaredCallback.to_issue(diag).message ==
             "@impl true for valid?/1 but no behaviour specifies such callback"
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {10, 1}}
    assert NoImplTrueForUndeclaredCallback.to_issue(diag).meta.line == 10
  end
end
