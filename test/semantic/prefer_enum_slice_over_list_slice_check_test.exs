defmodule Credence.Semantic.PreferEnumSliceOverListSliceCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferEnumSliceOverListSlice

  test "matches the diagnostic" do
    diag = %{
      severity: :warning,
      message: "List.slice/3 is undefined or private",
      position: {3, 5}
    }

    assert PreferEnumSliceOverListSlice.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferEnumSliceOverListSlice.match?(diag)
  end

  test "ignores non-warning severity" do
    diag = %{
      severity: :error,
      message: "List.slice/3 is undefined or private",
      position: {3, 5}
    }

    refute PreferEnumSliceOverListSlice.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :warning,
      message: "List.slice/3 is undefined or private",
      position: {3, 5}
    }

    assert PreferEnumSliceOverListSlice.to_issue(diag).rule == :prefer_enum_slice_over_list_slice
  end
end
