defmodule Credence.Semantic.PreferEnumJoinCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.PreferEnumJoin

  # The real warning Elixir emits for the nonexistent `String.join/2`.
  @real_message "String.join/2 is undefined or private"

  describe "match?/1" do
    test "matches the String.join undefined warning" do
      diag = %{severity: :warning, message: @real_message, position: {2, 28}}
      assert PreferEnumJoin.match?(diag)
    end

    test "matches when the compiler appends a suggestion" do
      diag = %{
        severity: :warning,
        message: "String.join/2 is undefined or private. Did you mean: Enum.join/2",
        position: {2, 28}
      }

      assert PreferEnumJoin.match?(diag)
    end

    # Regression: the generated rule keyed off the validator's "redefining
    # module" warning, so it fired on *any* module redefinition and reported a
    # bogus prefer_enum_join issue. It must NOT match that.
    test "does not match a redefining-module warning" do
      diag = %{
        severity: :warning,
        message:
          "redefining module Solution (current version loaded from " <>
            "_build/test/lib/workspace/ebin/Elixir.Solution.beam)",
        position: 1
      }

      refute PreferEnumJoin.match?(diag)
    end

    test "does not match another undefined function warning" do
      diag = %{
        severity: :warning,
        message: "Enum.bogus/1 is undefined or private",
        position: {2, 5}
      }

      refute PreferEnumJoin.match?(diag)
    end

    test "does not match error severity" do
      diag = %{severity: :error, message: @real_message, position: {2, 28}}
      refute PreferEnumJoin.match?(diag)
    end

    test "does not match an unrelated warning" do
      diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
      refute PreferEnumJoin.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "attributes the issue to this rule with the right line" do
      diag = %{severity: :warning, message: @real_message, position: {2, 28}}
      issue = PreferEnumJoin.to_issue(diag)
      assert issue.rule == :prefer_enum_join
      assert issue.meta.line == 2
    end

    test "handles bare integer position" do
      diag = %{severity: :warning, message: @real_message, position: 2}
      assert PreferEnumJoin.to_issue(diag).meta.line == 2
    end
  end

  describe "integration through Credence.Semantic" do
    test "detects String.join/2" do
      source = """
      defmodule EnumJoinCheckInteg1 do
        def render(list), do: String.join(list, ", ")
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :prefer_enum_join))
      refute Enum.empty?(matched)
    end

    test "no issue when Enum.join is used correctly" do
      source = """
      defmodule EnumJoinCheckInteg2 do
        def render(list), do: Enum.join(list, ", ")
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :prefer_enum_join))
      assert matched == []
    end
  end
end
