defmodule Credence.Semantic.FixStructUpdateOnDynamicVariableCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixStructUpdateOnDynamicVariable

  @real_message "a struct for AutocompleteTrie is expected on struct update:\n\n    %AutocompleteTrie{node | weight: weight}\n\nbut got type:\n\n    dynamic()\n\nwhere \"node\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:36:18\n    node\n\nwhen defining the variable \"node\", you must also pattern match on \"%AutocompleteTrie{}\".\n\nhint: given pattern matching is enough to catch typing errors, you may optionally convert the struct update into a map update. For example, instead of:\n\n    user = some_function()\n    %User{user | name: \"John Doe\"}\n\nit is enough to write:\n\n    %User{} = user = some_function()\n    %{user | name: \"John Doe\"}\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {38, 8}, file: "credence_check.ex"}
    assert FixStructUpdateOnDynamicVariable.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}, file: "credence_check.ex"}
    refute FixStructUpdateOnDynamicVariable.match?(diag)
  end

  test "ignores generic compile warning wrapper" do
    diag = %{
      severity: :warning,
      message: "credence_check.ex: cannot compile module (warnings have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixStructUpdateOnDynamicVariable.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {38, 8}, file: "credence_check.ex"}

    assert FixStructUpdateOnDynamicVariable.to_issue(diag).rule ==
             :fix_struct_update_on_dynamic_variable
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 5}, file: "credence_check.ex"}
    assert FixStructUpdateOnDynamicVariable.to_issue(diag).meta.line == 42
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {38, 8}, file: "credence_check.ex"}
    refute FixStructUpdateOnDynamicVariable.match?(diag)
  end
end
