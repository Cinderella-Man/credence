defmodule Credence.Semantic.NoUsePlugConnCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUsePlugConn

  @diag %{severity: :error, message: "function Plug.Conn.__using__/1 is undefined or private", position: {2, 3}, file: "credence_check.ex"}

  test "matches the diagnostic" do
    assert NoUsePlugConn.match?(@diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUsePlugConn.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoUsePlugConn.to_issue(@diag).rule == :no_use_plug_conn
  end
end
