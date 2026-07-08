defmodule Credence.Semantic.NoRemoteFunctionInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRemoteFunctionInGuard

  @real_message "cannot invoke remote function System.monotonic_time/1 inside a guard"

  defp fix(source, message \\ @real_message, line \\ 6) do
    NoRemoteFunctionInGuard.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "moves remote function guard into if/else body" do
    input = """
    defmodule MyModule do
      def check_timeout(start_time, timeout) do
        loop(start_time, timeout)
      end

      defp loop(start_time, timeout) when System.monotonic_time(:millisecond) - start_time >= timeout do
        :timeout
      end

      defp loop(start_time, timeout) do
        Process.sleep(10)
        loop(start_time, timeout)
      end
    end
    """

    expected = """
    defmodule MyModule do
      def check_timeout(start_time, timeout) do
        loop(start_time, timeout)
      end

      defp loop(start_time, timeout) do
        if System.monotonic_time(:millisecond) - start_time >= timeout do
          :timeout
        else
          Process.sleep(10)
          loop(start_time, timeout)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MyModule do
      defp loop(start_time, timeout) when System.monotonic_time(:millisecond) - start_time >= timeout do
        :timeout
      end

      defp loop(start_time, timeout) do
        Process.sleep(10)
        loop(start_time, timeout)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no remote function in guard" do
    input = """
    defmodule CleanExample do
      def check(x) when is_number(x), do: :ok
      def check(_x), do: :error
    end
    """

    confirm_fix(fix(input), input)
  end
end
