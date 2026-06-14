defmodule Credence.Syntax.NoDocWithDoBlockFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoDocWithDoBlock

  defp fix(code), do: NoDocWithDoBlock.fix(code)
  defp analyze(code), do: NoDocWithDoBlock.analyze(code)

  test "removes the stray do from @doc, rebalancing the module" do
    input = """
    defmodule Solution do
      @doc "top_n_items/2" do
      def find_top_n_items(map_data, n_items) do
        Enum.map(map_data, fn {key, value} -> {key, value} end)
      end
    end
    """

    expected = """
    defmodule Solution do
      @doc "top_n_items/2"
      def find_top_n_items(map_data, n_items) do
        Enum.map(map_data, fn {key, value} -> {key, value} end)
      end
    end
    """

    assert fix(input) == expected
  end

  test "removes the stray do from @moduledoc" do
    input = """
    @moduledoc "the module" do
    """

    expected = """
    @moduledoc "the module"
    """

    assert fix(input) == expected
  end

  test "leaves a proper @doc untouched" do
    source = """
    @doc "top_n_items/2"
    """

    assert fix(source) == source
  end

  test "leaves a real do block on a def untouched" do
    source = """
    def find(map, n) do
      Enum.take(map, n)
    end
    """

    assert fix(source) == source
  end

  test "leaves a @doc string ending in the word do untouched" do
    source = """
    @doc "explains what to do"
    """

    assert fix(source) == source
  end

  test "repairs more than one stray-do attribute in the same source" do
    input = """
    defmodule Solution do
      @moduledoc "m" do
      @doc "f/1" do
      def f(x), do: x
    end
    """

    expected = """
    defmodule Solution do
      @moduledoc "m"
      @doc "f/1"
      def f(x), do: x
    end
    """

    assert fix(input) == expected
  end

  test "fix clears the analyze flag (fixpoint)" do
    assert analyze(
             fix("""
             defmodule Solution do
               @doc "top_n_items/2" do
               def find(map, n), do: Enum.take(map, n)
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @doc "top_n_items/2" do
               def find_top_n_items(map_data, n_items) do
                 Enum.map(map_data, fn {key, value} -> {key, value} end)
               end
             end
             """)
           )
  end
end
