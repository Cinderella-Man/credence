defmodule Credence.Syntax.PreferScanOverScanlAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferScanOverScanl

  defp analyze(code), do: PreferScanOverScanl.analyze(code)

  test "flags code using Enum.scanl" do
    assert [%Issue{rule: :prefer_scan_over_scanl}] =
             analyze("Enum.scanl([1, 2, 3], 0, &+/2)")
  end

  test "flags Enum.scanl inside a module" do
    assert [%Issue{rule: :prefer_scan_over_scanl}] =
             analyze("""
             defmodule Solution do
               def prefix_sums(list) do
                 Enum.scanl(list, 0, &+/2)
               end
             end
             """)
  end

  test "reports the correct line number" do
    issues =
      analyze("""
      defmodule Solution do
        def prefix_sums(list) do
          Enum.scanl(list, 0, &+/2)
        end
      end
      """)

    assert [%Issue{meta: %{line: 3}}] = issues
  end

  test "leaves Enum.scan alone" do
    assert analyze("Enum.scan([1, 2, 3], 0, &+/2)") == []
  end

  test "leaves Enum.scan/2 alone" do
    assert analyze("Enum.scan([1, 2, 3], &+/2)") == []
  end

  test "leaves unrelated code alone" do
    assert analyze("Enum.map([1, 2, 3], &(&1 * 2))") == []
  end
end
