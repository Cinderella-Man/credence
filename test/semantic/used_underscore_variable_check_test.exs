defmodule Credence.Semantic.UsedUnderscoreVariableCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.UsedUnderscoreVariable

  describe "match?/1" do
    test "matches underscore variable used after being set" do
      diag = %{
        severity: :warning,
        message:
          ~s(the underscored variable "_target_n" is used after being set. ) <>
            "A leading underscore indicates that the value of the variable should be ignored.",
        position: {38, 90}
      }

      assert UsedUnderscoreVariable.match?(diag)
    end

    test "matches shorter form of the message" do
      diag = %{
        severity: :warning,
        message: ~s(variable "_x" is used after being set),
        position: {5, 1}
      }

      assert UsedUnderscoreVariable.match?(diag)
    end

    test "does not match error severity" do
      diag = %{
        severity: :error,
        message: ~s(variable "_x" is used after being set),
        position: {5, 1}
      }

      refute UsedUnderscoreVariable.match?(diag)
    end

    test "does not match unused variable warning" do
      diag = %{
        severity: :warning,
        message: ~s(variable "x" is unused),
        position: {5, 6}
      }

      refute UsedUnderscoreVariable.match?(diag)
    end

    test "does not match unrelated warning" do
      diag = %{
        severity: :warning,
        message: "function helper/1 is unused",
        position: {5, 6}
      }

      refute UsedUnderscoreVariable.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line from tuple position" do
      diag = %{
        severity: :warning,
        message: ~s(variable "_target_n" is used after being set),
        position: {38, 90}
      }

      issue = UsedUnderscoreVariable.to_issue(diag)
      assert issue.rule == :used_underscore_variable
      assert issue.meta.line == 38
      assert issue.message =~ "_target_n"
    end

    test "builds issue with bare integer position" do
      diag = %{
        severity: :warning,
        message: ~s(variable "_x" is used after being set),
        position: 5
      }

      issue = UsedUnderscoreVariable.to_issue(diag)
      assert issue.meta.line == 5
    end
  end

  describe "integration through Credence.Semantic" do
    test "detects underscore variable used in guard" do
      source = """
      defmodule UsedUnderscoreCheckInteg1 do
        def check(_limit, value) when value > _limit, do: :over
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :used_underscore_variable))
      assert length(matched) >= 1
    end

    test "detects underscore variable used in body" do
      source = """
      defmodule UsedUnderscoreCheckInteg2 do
        def check(_limit, value) do
          value + _limit
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :used_underscore_variable))
      assert length(matched) >= 1
    end

    test "no issues when underscore variable is truly unused" do
      source = """
      defmodule UsedUnderscoreCheckInteg3 do
        def check(_limit, value), do: value
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :used_underscore_variable))
      assert matched == []
    end

    test "no issues when variable has no underscore prefix" do
      source = """
      defmodule UsedUnderscoreCheckInteg4 do
        def check(limit, value) when value > limit, do: :over
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :used_underscore_variable))
      assert matched == []
    end
  end
end
