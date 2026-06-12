defmodule Credence.Semantic.PreferMapSizeKernelCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferMapSizeKernel

  test "matches the diagnostic" do
    diag = %{
      severity: :warning,
      message: "Map.size/1 is deprecated. Use map_size/1 instead.",
      position: {3, 5}
    }

    assert PreferMapSizeKernel.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferMapSizeKernel.match?(diag)
  end

  test "ignores non-warning severity" do
    diag = %{
      severity: :error,
      message: "Map.size/1 is deprecated. Use map_size/1 instead.",
      position: {3, 5}
    }

    refute PreferMapSizeKernel.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :warning,
      message: "Map.size/1 is deprecated. Use map_size/1 instead.",
      position: {3, 5}
    }

    assert PreferMapSizeKernel.to_issue(diag).rule == :prefer_map_size_kernel
  end
end
