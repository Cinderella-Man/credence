defmodule Credence.Semantic.NoGenserverCastWithRaiseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoGenserverCastWithRaise

  @real_message ~s(got "@impl true" for function init/1 but no behaviour was declared)

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {40, 1}}
    assert NoGenserverCastWithRaise.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoGenserverCastWithRaise.match?(diag)
  end

  test "ignores errors" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute NoGenserverCastWithRaise.match?(diag)
  end

  test "does not match the other @impl true diagnostic" do
    diag = %{
      severity: :warning,
      message: ~s(got "@impl true" for function handle_call/3 but no behaviour specifies such callback),
      position: {1, 1}
    }

    refute NoGenserverCastWithRaise.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {40, 1}}
    assert NoGenserverCastWithRaise.to_issue(diag).rule == :no_genserver_cast_with_raise
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoGenserverCastWithRaise.to_issue(diag).meta.line == 42
  end
end
