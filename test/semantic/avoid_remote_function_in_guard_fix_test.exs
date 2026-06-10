defmodule Credence.Semantic.AvoidRemoteFunctionInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.AvoidRemoteFunctionInGuard

  defp fix(source, message \\ nil, line \\ 1) do
    msg = message || "cannot invoke remote function MapSet.size/1 inside a guard"

    AvoidRemoteFunctionInGuard.fix(source, %{
      severity: :error,
      message: msg,
      position: {line, 1}
    })
  end

  test "merges guarded clause with fallback into if/else" do
    input = """
    defmodule Example do
      defp count_components_dfs(_adj, unvisited, _visited, count) when MapSet.size(unvisited) == 0 do
        count
      end

      defp count_components_dfs(adj, unvisited, _visited, count) do
        count + 1
      end
    end
    """

    expected = """
    defmodule Example do
      defp count_components_dfs(_adj, unvisited, _visited, count) do
        if MapSet.size(unvisited) == 0 do
          count
        else
          count + 1
        end
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      defp count_components_dfs(_adj, unvisited, _visited, count) when MapSet.size(unvisited) == 0 do
        count
      end

      defp count_components_dfs(adj, unvisited, _visited, count) do
        count + 1
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no remote function in guard" do
    input = """
    defmodule Example do
      defp foo(x) when x > 0, do: x
      defp foo(x), do: -x
    end
    """

    assert fix(input) == input
  end

  test "returns source unchanged when no consecutive defp pair" do
    input = """
    defmodule Example do
      defp foo(x) when MapSet.size(x) == 0, do: :empty

      def bar(x), do: x

      defp foo(x), do: x
    end
    """

    assert fix(input) == input
  end

  test "handles guard with List.first/1 remote call" do
    input = """
    defmodule Example do
      defp process(list, acc) when List.first(list) == nil do
        acc
      end

      defp process(list, acc) do
        [head | tail] = list
        process(tail, [head | acc])
      end
    end
    """

    expected = """
    defmodule Example do
      defp process(list, acc) do
        if List.first(list) == nil do
          acc
        else
          [head | tail] = list
          process(tail, [head | acc])
        end
      end
    end
    """

    assert fix(input) == expected
  end

  test "handles guard with String.length/1 remote call" do
    input = """
    defmodule Example do
      defp classify(str) when String.length(str) == 0 do
        :empty
      end

      defp classify(str) do
        :non_empty
      end
    end
    """

    expected = """
    defmodule Example do
      defp classify(str) do
        if String.length(str) == 0 do
          :empty
        else
          :non_empty
        end
      end
    end
    """

    assert fix(input) == expected
  end

  test "does not modify source without remote function calls in guard" do
    input = """
    defmodule Example do
      defp foo(x) when is_integer(x) and x > 0, do: x
      defp foo(x), do: -x
    end
    """

    assert fix(input) == input
  end
end
