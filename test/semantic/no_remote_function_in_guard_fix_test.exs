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

  test "decomposes compound and guard: keeps safe part in when, moves remote call to if" do
    input = """
    defmodule MapHasKeyInGuardDemo do
      def find_cycle(node_id, parent_map, path_set, path_list) do
        parent = Map.get(parent_map, node_id)

        case parent do
          nil ->
            :no_cycle

          pid when not is_nil(pid) and Map.has_key?(parent_map, pid) ->
            find_cycle(pid, parent_map, path_set, path_list ++ [node_id])

          _ ->
            :no_cycle
        end
      end
    end
    """

    expected = """
    defmodule MapHasKeyInGuardDemo do
      def find_cycle(node_id, parent_map, path_set, path_list) do
        parent = Map.get(parent_map, node_id)

        case parent do
          nil ->
            :no_cycle

          pid when not is_nil(pid) ->
            if Map.has_key?(parent_map, pid) do
              find_cycle(pid, parent_map, path_set, path_list ++ [node_id])
            else
              :no_cycle
            end

          _ ->
            :no_cycle
        end
      end
    end
    """

    message = "cannot invoke remote function Map.has_key?/2 inside a guard"
    confirm_fix(fix(input, message, 9), expected)
  end

  test "compound guard fix output is well-formed (parses)" do
    input = """
    defmodule MapHasKeyInGuardDemo do
      def find_cycle(node_id, parent_map, path_set, path_list) do
        parent = Map.get(parent_map, node_id)

        case parent do
          nil ->
            :no_cycle

          pid when not is_nil(pid) and Map.has_key?(parent_map, pid) ->
            find_cycle(pid, parent_map, path_set, path_list ++ [node_id])

          _ ->
            :no_cycle
        end
      end
    end
    """

    message = "cannot invoke remote function Map.has_key?/2 inside a guard"
    assert valid_syntax?(fix(input, message, 9))
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
