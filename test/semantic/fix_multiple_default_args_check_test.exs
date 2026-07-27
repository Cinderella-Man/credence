defmodule Credence.Semantic.FixMultipleDefaultArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixMultipleDefaultArgs

  @real_message "def greet/2 defines defaults multiple times. Elixir allows defaults to be declared once per definition. Instead of:\n\n    def foo(:first_clause, b \\ :default) do ... end\n    def foo(:second_clause, b \\ :default) do ... end\n\none should write:\n\n    def foo(a, b \\ :default)\n    def foo(:first_clause, b) do ... end\n    def foo(:second_clause, b) do ... end\n\nthe previous clause is defined on line 2\n"

  @impl_message "module attribute @impl was not set for function monotonic/1 callback (specified in Clock). This either means you forgot to add the \"@impl true\" annotation before the definition or that you are accidentally overriding this callback"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert FixMultipleDefaultArgs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "undefined function foo/1", position: {1, 1}}
    refute FixMultipleDefaultArgs.match?(diag)
  end

  test "ignores warning severity for defines defaults multiple times" do
    diag = %{severity: :warning, message: @real_message, position: {6, 7}}
    refute FixMultipleDefaultArgs.match?(diag)
  end

  test "matches @impl missing for callback" do
    diag = %{severity: :warning, message: @impl_message, position: {69, 1}}
    assert FixMultipleDefaultArgs.match?(diag)
  end

  test "ignores @impl warning without callback" do
    diag = %{severity: :warning, message: "module attribute @impl was not set for function foo/1", position: {1, 1}}
    refute FixMultipleDefaultArgs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert FixMultipleDefaultArgs.to_issue(diag).rule == :fix_multiple_default_args
  end

  test "extracts the function name in the issue message" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert FixMultipleDefaultArgs.to_issue(diag).message =~ "greet/2"
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert FixMultipleDefaultArgs.to_issue(diag).meta.line == 6
  end

  test "attributes @impl issue to this rule" do
    diag = %{severity: :warning, message: @impl_message, position: {69, 1}}
    assert FixMultipleDefaultArgs.to_issue(diag).rule == :fix_multiple_default_args
  end

  test "extracts function name from @impl issue message" do
    diag = %{severity: :warning, message: @impl_message, position: {69, 1}}
    assert FixMultipleDefaultArgs.to_issue(diag).message =~ "monotonic/1"
  end
end
