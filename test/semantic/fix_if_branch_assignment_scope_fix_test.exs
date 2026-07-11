defmodule Credence.Semantic.FixIfBranchAssignmentScopeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixIfBranchAssignmentScope

  @message "undefined variable \"new_service\""

  defp fix(source, message, line \\ 1) do
    FixIfBranchAssignmentScope.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes if branch assignment hoisting" do
    input = ~S"""
    defmodule M do
      def check(state) do
        if state.paused do
          new_service = Map.put(state, :timer_ref, nil)
          {:paused, new_service}
        else
          new_service = %{state | status: :active}
          {:active, new_service}
        end

        Map.put(new_service, :checked, true)
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def check(state) do
        new_service =
          if state.paused do
            new_service = Map.put(state, :timer_ref, nil)
            {:paused, new_service}
            new_service
          else
            new_service = %{state | status: :active}
            {:active, new_service}
            new_service
          end

        Map.put(new_service, :checked, true)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixes if with simple branch bodies" do
    input = ~S"""
    defmodule M do
      def check(x) do
        if x > 0 do
          val = x * 2
        else
          val = 0
        end

        val + 1
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def check(x) do
        val =
          if x > 0 do
            val = x * 2
            val
          else
            val = 0
            val
          end

        val + 1
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"val\""), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule M do
      def check(state) do
        if state.paused do
          new_service = Map.put(state, :timer_ref, nil)
          {:paused, new_service}
        else
          new_service = %{state | status: :active}
          {:active, new_service}
        end

        Map.put(new_service, :checked, true)
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no if branch assignment pattern" do
    input = ~S"""
    defmodule M do
      def check(x) do
        val = if x > 0, do: x * 2, else: 0
        val + 1
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "returns source unchanged when variable is not used after if" do
    input = ~S"""
    defmodule M do
      def check(state) do
        if state.paused do
          new_service = Map.put(state, :timer_ref, nil)
          {:paused, new_service}
        else
          new_service = %{state | status: :active}
          {:active, new_service}
        end

        :ok
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
