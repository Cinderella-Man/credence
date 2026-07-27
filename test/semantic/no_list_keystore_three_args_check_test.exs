defmodule Credence.Semantic.NoListKeystoreThreeArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoListKeystoreThreeArgs

  @real_message "List.keystore/3 is undefined or private. Did you mean:\n\n    * keystore/4\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 10}}
    assert NoListKeystoreThreeArgs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoListKeystoreThreeArgs.match?(diag)
  end

  test "ignores module redefinition warning" do
    diag = %{
      severity: :warning,
      message:
        "redefining module FilteredEventBus (current version loaded from _build/test/lib/workspace/ebin/Elixir.FilteredEventBus.beam)",
      position: 1
    }

    refute NoListKeystoreThreeArgs.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {3, 10}}
    refute NoListKeystoreThreeArgs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 10}}
    assert NoListKeystoreThreeArgs.to_issue(diag).rule == :no_list_keystore_three_args
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoListKeystoreThreeArgs.to_issue(diag).meta.line == 42
  end
end
