defmodule Credence.Semantic.PreferTlOverEnumTailCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferTlOverEnumTail

  # The real warning Elixir emits for the nonexistent `Enum.tail/1`.
  @real_message "Enum.tail/1 is undefined or private"

  describe "match?/1" do
    test "matches the Enum.tail undefined warning" do
      diag = %{severity: :warning, message: @real_message, position: {11, 5}}
      assert PreferTlOverEnumTail.match?(diag)
    end

    test "matches when the compiler appends a suggestion" do
      diag = %{
        severity: :warning,
        message: "Enum.tail/1 is undefined or private. Did you mean: tl/1",
        position: {11, 5}
      }

      assert PreferTlOverEnumTail.match?(diag)
    end

    # The "redefining module" warning is a common side-effect when the test
    # harness compiles code that redefines an already-loaded module. The rule
    # must NOT match it.
    test "does not match a redefining-module warning" do
      diag = %{
        severity: :warning,
        message:
          "redefining module Solution (current version loaded from " <>
            "_build/test/lib/workspace/ebin/Elixir.Solution.beam)",
        position: 1
      }

      refute PreferTlOverEnumTail.match?(diag)
    end

    test "does not match another undefined function warning" do
      diag = %{
        severity: :warning,
        message: "Enum.bogus/1 is undefined or private",
        position: {2, 5}
      }

      refute PreferTlOverEnumTail.match?(diag)
    end

    test "does not match error severity" do
      diag = %{severity: :error, message: @real_message, position: {11, 5}}
      refute PreferTlOverEnumTail.match?(diag)
    end

    test "does not match an unrelated warning" do
      diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
      refute PreferTlOverEnumTail.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "attributes the issue to this rule with the right line" do
      diag = %{severity: :warning, message: @real_message, position: {11, 5}}
      issue = PreferTlOverEnumTail.to_issue(diag)
      assert issue.rule == :prefer_tl_over_enum_tail
      assert issue.meta.line == 11
    end

    test "handles bare integer position" do
      diag = %{severity: :warning, message: @real_message, position: 11}
      assert PreferTlOverEnumTail.to_issue(diag).meta.line == 11
    end
  end
end
