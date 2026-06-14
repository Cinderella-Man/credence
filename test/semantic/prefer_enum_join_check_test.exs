defmodule Credence.Semantic.PreferEnumJoinCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferEnumJoin

  test "matches the diagnostic" do
    diag = %{
      severity: :warning,
      message:
        "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)",
      position: 1
    }

    assert PreferEnumJoin.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferEnumJoin.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :warning,
      message:
        "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)",
      position: 1
    }

    assert PreferEnumJoin.to_issue(diag).rule == :prefer_enum_join
  end
end
