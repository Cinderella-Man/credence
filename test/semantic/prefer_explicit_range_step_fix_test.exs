defmodule Credence.Semantic.PreferExplicitRangeStepFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferExplicitRangeStep

  defp fix(source, range) do
    msg = "#{range} has a default step of -1, please write #{range}//-1 instead"
    PreferExplicitRangeStep.fix(source, %{severity: :warning, message: msg, position: 0})
  end

  test "appends the explicit step the compiler reports" do
    confirm_fix(fix("Enum.slice(list, 1..-2)", "1..-2"), "Enum.slice(list, 1..-2//-1)")
  end

  test "handles a descending all-positive literal range" do
    confirm_fix(fix("for i <- 5..1, do: i", "5..1"), "for i <- 5..1//-1, do: i")
  end

  test "fixed output parses" do
    assert valid_syntax?(fix("Enum.slice(list, 10..-5)", "10..-5"))
  end

  test "rewrites every occurrence of the same range" do
    confirm_fix(
      fix("{Enum.take(a, 1..-2), Enum.take(b, 1..-2)}", "1..-2"),
      "{Enum.take(a, 1..-2//-1), Enum.take(b, 1..-2//-1)}"
    )
  end

  # Boundary safety: the range token must not match inside a longer number or
  # an already-stepped range.

  test "does not corrupt a longer range that shares a prefix (1..-20)" do
    confirm_fix(fix("Enum.take(a, 1..-20)", "1..-2"), "Enum.take(a, 1..-20)")
  end

  test "does not match the suffix of a longer left endpoint (11..-2)" do
    confirm_fix(fix("Enum.take(a, 11..-2)", "1..-2"), "Enum.take(a, 11..-2)")
  end

  test "is idempotent on an already-stepped range" do
    confirm_fix(fix("Enum.slice(list, 1..-2//-1)", "1..-2"), "Enum.slice(list, 1..-2//-1)")
  end

  test "leaves source unchanged on a malformed message" do
    src = "Enum.slice(list, 1..-2)"
    out = PreferExplicitRangeStep.fix(src, %{severity: :warning, message: "garbage", position: 0})
    confirm_fix(out, src)
  end
end
