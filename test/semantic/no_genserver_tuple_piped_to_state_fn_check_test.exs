defmodule Credence.Semantic.NoGenserverTuplePipedToStateFnCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoGenserverTuplePipedToStateFn

  @match_message "GenServer reply tuple piped into helper function"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_message, position: {1, 1}}
    assert NoGenserverTuplePipedToStateFn.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoGenserverTuplePipedToStateFn.match?(diag)
  end

  test "ignores errors" do
    diag = %{severity: :error, message: @match_message, position: {1, 1}}
    refute NoGenserverTuplePipedToStateFn.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_message, position: {1, 1}}

    assert NoGenserverTuplePipedToStateFn.to_issue(diag).rule ==
             :no_genserver_tuple_piped_to_state_fn
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @match_message, position: {42, 10}}
    assert NoGenserverTuplePipedToStateFn.to_issue(diag).meta.line == 42
  end
end
