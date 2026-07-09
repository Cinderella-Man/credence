defmodule Credence.Semantic.NoPrivateFnInTimerMfaFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoPrivateFnInTimerMfa

  defp fix(source, message, line \\ 1) do
    NoPrivateFnInTimerMfa.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "promotes defp to def when referenced via :timer.apply_after MFA" do
    input = """
    defmodule TimerPrivateFn do
      def schedule_cleanup(pid, ms) do
        {:ok, _ref} = :timer.apply_after(ms, __MODULE__, :do_cleanup, [pid])
        :ok
      end

      defp do_cleanup(pid) do
        Process.exit(pid, :cleanup)
      end
    end
    """

    expected = """
    defmodule TimerPrivateFn do
      def schedule_cleanup(pid, ms) do
        {:ok, _ref} = :timer.apply_after(ms, __MODULE__, :do_cleanup, [pid])
        :ok
      end

      def do_cleanup(pid) do
        Process.exit(pid, :cleanup)
      end
    end
    """

    message = "function do_cleanup/1 is unused"
    confirm_fix(fix(input, message, 7), expected)
  end

  test "promotes defp to def when referenced via :timer.apply_interval MFA" do
    input = """
    defmodule TimerInterval do
      def start_periodic(pid, ms) do
        {:ok, _ref} = :timer.apply_interval(ms, __MODULE__, :tick, [pid])
        :ok
      end

      defp tick(pid) do
        send(pid, :tick)
      end
    end
    """

    expected = """
    defmodule TimerInterval do
      def start_periodic(pid, ms) do
        {:ok, _ref} = :timer.apply_interval(ms, __MODULE__, :tick, [pid])
        :ok
      end

      def tick(pid) do
        send(pid, :tick)
      end
    end
    """

    message = "function tick/1 is unused"
    confirm_fix(fix(input, message, 7), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TimerPrivateFn do
      def schedule_cleanup(pid, ms) do
        {:ok, _ref} = :timer.apply_after(ms, __MODULE__, :do_cleanup, [pid])
        :ok
      end

      defp do_cleanup(pid) do
        Process.exit(pid, :cleanup)
      end
    end
    """

    message = "function do_cleanup/1 is unused"
    assert valid_syntax?(fix(input, message, 7))
  end

  test "returns source unchanged when function is not referenced via timer MFA" do
    input = """
    defmodule UnusedHelper do
      defp helper(x), do: x + 1
    end
    """

    message = "function helper/1 is unused"
    confirm_fix(fix(input, message), input)
  end

  test "returns source unchanged when defp line not found" do
    input = """
    defmodule SomeModule do
      def foo, do: :ok
    end
    """

    message = "function bar/1 is unused"
    confirm_fix(fix(input, message), input)
  end
end
