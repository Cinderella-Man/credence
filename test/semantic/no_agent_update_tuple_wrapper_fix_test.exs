defmodule Credence.Semantic.NoAgentUpdateTupleWrapperFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoAgentUpdateTupleWrapper

  @match_msg "Agent.update callback should return new state, not {:ok, state}"

  defp fix(source, message \\ @match_msg, line \\ 1) do
    NoAgentUpdateTupleWrapper.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "unwraps {:ok, state} in Agent.update callback" do
    input = """
    defmodule BadAgentUpdate do
      use Agent

      def start_link do
        Agent.start_link(fn -> %{count: 0} end, name: __MODULE__)
      end

      def increment do
        Agent.update(__MODULE__, fn state ->
          new = state.count + 1
          {:ok, %{state | count: new}}
        end)
      end

      def count do
        Agent.get(__MODULE__, fn state -> state.count end)
      end
    end
    """

    expected = """
    defmodule BadAgentUpdate do
      use Agent

      def start_link do
        Agent.start_link(fn -> %{count: 0} end, name: __MODULE__)
      end

      def increment do
        Agent.update(__MODULE__, fn state ->
          new = state.count + 1
          %{state | count: new}
        end)
      end

      def count do
        Agent.get(__MODULE__, fn state -> state.count end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "unwraps single-expression {:ok, state} callback" do
    input = """
    defmodule SimpleAgent do
      def update(pid) do
        Agent.update(pid, fn state ->
          {:ok, %{state | x: 1}}
        end)
      end
    end
    """

    expected = """
    defmodule SimpleAgent do
      def update(pid) do
        Agent.update(pid, fn state ->
          %{state | x: 1}
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "returns source unchanged when callback already returns bare state" do
    input = """
    defmodule GoodAgent do
      def update(pid) do
        Agent.update(pid, fn state -> %{state | x: 1} end)
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule BadAgentUpdate do
      def increment do
        Agent.update(__MODULE__, fn state ->
          new = state.count + 1
          {:ok, %{state | count: new}}
        end)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
