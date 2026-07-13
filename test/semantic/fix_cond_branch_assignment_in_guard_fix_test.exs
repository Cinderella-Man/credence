defmodule Credence.Semantic.FixCondBranchAssignmentInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixCondBranchAssignmentInGuard

  @message "undefined variable \"user_key\""

  defp fix(source, message, line \\ 1) do
    FixCondBranchAssignmentInGuard.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "restructures cond with guard assignment into nested ifs" do
    input = ~S"""
    defmodule CondGuardAssignment do
      def check(code, user_id, usages) do
        cond do
          code.max_uses_per_user && user_id ->
            user_key = {code.code, user_id}
            Map.get(usages, user_key, 0) >= code.max_uses_per_user ->
              :exceeded

          true ->
            :ok
        end
      end
    end
    """

    expected = ~S"""
    defmodule CondGuardAssignment do
      def check(code, user_id, usages) do
        if code.max_uses_per_user && user_id do
          user_key = {code.code, user_id}

          if Map.get(usages, user_key, 0) >= code.max_uses_per_user do
            :exceeded
          else
            :ok
          end
        else
          :ok
        end
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule CondGuardAssignment do
      def check(code, user_id, usages) do
        cond do
          code.max_uses_per_user && user_id ->
            user_key = {code.code, user_id}
            Map.get(usages, user_key, 0) >= code.max_uses_per_user ->
              :exceeded

          true ->
            :ok
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no guard assignment pattern" do
    input = ~S"""
    defmodule CleanModule do
      def check(x) do
        cond do
          x > 0 -> :positive
          true -> :non_positive
        end
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "returns source unchanged when variable is used after cond block (not in guard)" do
    input = ~S"""
    defmodule M do
      def calc(values) do
        wma1_val =
          cond do
            true ->
              Enum.sum(values)
            false ->
              0
          end

        wma1_val * 2
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"wma1_val\""), input)
  end
end
