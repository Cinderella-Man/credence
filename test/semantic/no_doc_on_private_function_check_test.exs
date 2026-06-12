defmodule Credence.Semantic.NoDocOnPrivateFunctionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoDocOnPrivateFunction

  @doc_diag %{
    severity: :warning,
    message: "defp build_order_map/1 is private, @doc attribute is always discarded for private functions/macros/types",
    position: 18,
    file: "credence_check.ex",
    source: "credence_check.ex"
  }

  test "matches the diagnostic" do
    assert NoDocOnPrivateFunction.match?(@doc_diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoDocOnPrivateFunction.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoDocOnPrivateFunction.to_issue(@doc_diag).rule == :no_doc_on_private_function
  end
end
