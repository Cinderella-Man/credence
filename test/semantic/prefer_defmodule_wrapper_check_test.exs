defmodule Credence.Semantic.PreferDefmoduleWrapperCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferDefmoduleWrapper

  test "matches the diagnostic" do
    diag = %{severity: :error, message: "cannot invoke @/1 outside module", position: {1, 1}}
    assert PreferDefmoduleWrapper.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferDefmoduleWrapper.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: "cannot invoke @/1 outside module", position: {1, 1}}
    assert PreferDefmoduleWrapper.to_issue(diag).rule == :prefer_defmodule_wrapper
  end
end