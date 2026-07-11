defmodule Credence.Semantic.NoMapsetMemberInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoMapsetMemberInGuard

  @real_message "cannot invoke remote function MapSet.member?/2 inside a guard"

  defp fix(source, message \\ @real_message, line \\ 2) do
    NoMapsetMemberInGuard.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "converts MapSet.member? guard into if/else body" do
    input = """
    defmodule CycleCheck do
      defp cycle_check(graph, node, visited, rec_stack) when MapSet.member?(rec_stack, node), do: true

      defp cycle_check(graph, node, visited, rec_stack) do
        visited = MapSet.put(visited, node)
        rec_stack = MapSet.put(rec_stack, node)

        neighbors = Map.get(graph, node, [])

        Enum.any?(neighbors, fn neighbor ->
          if MapSet.member?(visited, neighbor) do
            false
          else
            cycle_check(graph, neighbor, visited, rec_stack)
          end
        end)
      end
    end
    """

    expected = """
    defmodule CycleCheck do
      defp cycle_check(graph, node, visited, rec_stack) do
        if MapSet.member?(rec_stack, node) do
          true
        else
          visited = MapSet.put(visited, node)
          rec_stack = MapSet.put(rec_stack, node)

          neighbors = Map.get(graph, node, [])

          Enum.any?(neighbors, fn neighbor ->
            if MapSet.member?(visited, neighbor) do
              false
            else
              cycle_check(graph, neighbor, visited, rec_stack)
            end
          end)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "simple two-clause merge" do
    input = """
    defmodule SimpleCheck do
      defp check(x, set) when MapSet.member?(set, x), do: true
      defp check(_, _), do: false
    end
    """

    expected = """
    defmodule SimpleCheck do
      defp check(x, set) do
        if MapSet.member?(set, x) do
          true
        else
          false
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule CycleCheck do
      defp cycle_check(graph, node, visited, rec_stack) when MapSet.member?(rec_stack, node), do: true

      defp cycle_check(graph, node, visited, rec_stack) do
        false
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no MapSet.member? in guard" do
    input = """
    defmodule CleanExample do
      def check(x) when is_number(x), do: :ok
      def check(_x), do: :error
    end
    """

    confirm_fix(fix(input), input)
  end
end
