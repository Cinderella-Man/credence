defmodule Credence.Semantic.FixPythonStyleStructDefinitionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixPythonStyleStructDefinition

  @message "Node.__struct__/1 is undefined, cannot expand struct Node. Make sure the struct name is correct. If the struct name exists and is correct but it still cannot be found, you likely have cyclic module usage in your code"

  defp fix(source, message, line \\ 1) do
    FixPythonStyleStructDefinition.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces defp struct with defstruct and rewrites %Name{} to %__MODULE__{}" do
    input = ~S"""
    defmodule IntervalTree do
      def new(), do: nil

      def insert(nil, interval), do: %Node{interval: interval, max: elem(interval, 1), left: nil, right: nil, height: 1}
      def insert(root, interval), do: balance(insert_node(root, interval))

      def overlapping(nil, _query), do: []

      defp struct Node do
        %{
          interval: {integer, integer},
          max: integer,
          left: any,
          right: any,
          height: integer
        }
      end

      defp insert_node(nil, interval), do: %Node{interval: interval, max: elem(interval, 1), left: nil, right: nil, height: 1}

      defp balance(node), do: node
    end
    """

    expected = ~S"""
    defmodule IntervalTree do
      def new(), do: nil

      def insert(nil, interval), do: %__MODULE__{interval: interval, max: elem(interval, 1), left: nil, right: nil, height: 1}
      def insert(root, interval), do: balance(insert_node(root, interval))

      def overlapping(nil, _query), do: []

      defstruct [:interval, :max, :left, :right, :height]

      defp insert_node(nil, interval), do: %__MODULE__{interval: interval, max: elem(interval, 1), left: nil, right: nil, height: 1}

      defp balance(node), do: node
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule IntervalTree do
      def new(), do: nil

      def insert(nil, interval), do: %Node{interval: interval, max: elem(interval, 1), left: nil, right: nil, height: 1}
      def insert(root, interval), do: balance(insert_node(root, interval))

      def overlapping(nil, _query), do: []

      defp struct Node do
        %{
          interval: {integer, integer},
          max: integer,
          left: any,
          right: any,
          height: integer
        }
      end

      defp insert_node(nil, interval), do: %Node{interval: interval, max: elem(interval, 1), left: nil, right: nil, height: 1}

      defp balance(node), do: node
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no defp struct pattern" do
    input = ~S"""
    defmodule Factory do
      def build(:user) do
        %MyApp.User{name: "test"}
      end
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated error message" do
    input = ~S"""
    defmodule Example do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, "unrelated error")
    confirm_fix(result, input)
  end
end
