defmodule Credence.Semantic.NoMessageAccessOnRescueVariableCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoMessageAccessOnRescueVariable

  @real_message "unknown key .message in expression:\n\n    e.message\n\nthe given type does not have the given key:\n\n    %{..., __exception__: true, __struct__: atom()}\n\nwhere \"e\" was given the type:\n\n    # type: %{..., __exception__: true, __struct__: atom()}\n    # from: nofile\n    rescue e\n\nhint: when you rescue without specifying exception names, the variable is assigned a type of a struct but all of its fields are unknown. If you are trying to access an exception's :message key, either specify the exception names or use `Exception.message/1`.\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {9, 25}}
    assert NoMessageAccessOnRescueVariable.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoMessageAccessOnRescueVariable.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {9, 25}}

    assert NoMessageAccessOnRescueVariable.to_issue(diag).rule ==
             :no_message_access_on_rescue_variable
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 5}}
    assert NoMessageAccessOnRescueVariable.to_issue(diag).meta.line == 42
  end
end
