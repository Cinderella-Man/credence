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

  test "replaces Map.get struct identity guard with struct pattern in function head" do
    input = """
    defmodule Example do
      @email_regex ~r/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/

      defp validate_format(value, format) when is_binary(format) or is_atom(format) do
        case format do
          :email -> Regex.match?(@email_regex, value)
          _ ->
            case Regex.compile(format) do
              {:ok, regex} -> Regex.match?(regex, value)
              {:error, _} -> false
            end
        end
      end

      defp validate_format(value, regex) when is_map(regex) and Map.get(regex, :__struct__) == Regex do
        Regex.match?(regex, value)
      end
    end
    """

    expected = """
    defmodule Example do
      @email_regex ~r/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/

      defp validate_format(value, format) when is_binary(format) or is_atom(format) do
        case format do
          :email ->
            Regex.match?(@email_regex, value)

          _ ->
            case Regex.compile(format) do
              {:ok, regex} -> Regex.match?(regex, value)
              {:error, _} -> false
            end
        end
      end

      defp validate_format(value, %Regex{} = regex) do
        Regex.match?(regex, value)
      end
    end
    """

    message = "cannot invoke remote function Map.get/2 inside a guard"
    confirm_fix(fix(input, message, 15), expected)
  end

  test "struct pattern fix output is well-formed (parses)" do
    input = """
    defmodule Example do
      defp validate_format(value, regex) when is_map(regex) and Map.get(regex, :__struct__) == Regex do
        Regex.match?(regex, value)
      end
    end
    """

    message = "cannot invoke remote function Map.get/2 inside a guard"
    assert valid_syntax?(fix(input, message, 2))
  end

  test "compound guard with safe remainder preserves fallback clause and uses keyword syntax" do
    input = """
    defmodule FixTest do
      defp validate_name(name) when is_binary(name) and String.length(name) > 0, do: :ok
      defp validate_name(_), do: {:error, :invalid_name}
    end
    """

    expected = """
    defmodule FixTest do
      defp validate_name(name) when is_binary(name) do
        if String.length(name) > 0 do
          :ok
        else
          {:error, :invalid_name}
        end
      end

      defp validate_name(_), do: {:error, :invalid_name}
    end
    """

    message = "cannot invoke remote function String.length/1 inside a guard"
    confirm_fix(fix(input, message, 2), expected)
  end

  test "compound guard with safe remainder produces valid syntax" do
    input = """
    defmodule FixTest do
      defp validate_name(name) when is_binary(name) and String.length(name) > 0, do: :ok
      defp validate_name(_), do: {:error, :invalid_name}
    end
    """

    message = "cannot invoke remote function String.length/1 inside a guard"
    assert valid_syntax?(fix(input, message, 2))
  end
end
