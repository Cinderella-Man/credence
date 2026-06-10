defmodule Credence.Semantic.PreferKernelMaxOverLocalCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferKernelMaxOverLocal

  test "matches the diagnostic" do
    diag = %{
      severity: :error,
      message: "imported Kernel.max/2 conflicts with local function",
      position: {6, 8}
    }

    assert PreferKernelMaxOverLocal.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferKernelMaxOverLocal.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message: "imported Kernel.max/2 conflicts with local function",
      position: {6, 8}
    }

    assert PreferKernelMaxOverLocal.to_issue(diag).rule == :prefer_kernel_max_over_local
  end
end
