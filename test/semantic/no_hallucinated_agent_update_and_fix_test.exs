defmodule Credence.Semantic.NoHallucinatedAgentUpdateAndFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedAgentUpdateAnd

  @warning_message "Agent.update_and/2 is undefined or private. Did you mean:\n\n    * update/2\n    * update/3\n    * update/4\n    * update/5\n"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedAgentUpdateAnd.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces Agent.update_and with Agent.get_and_update" do
    input = """
    defmodule HallucinatedAgentUpdateAnd do
      def next(agent_name, formatter_fn) do
        Agent.update_and(agent_name, fn counter ->
          new_counter = counter + 1
          {formatter_fn.(new_counter), new_counter}
        end)
      end
    end
    """

    expected = """
    defmodule HallucinatedAgentUpdateAnd do
      def next(agent_name, formatter_fn) do
        Agent.get_and_update(agent_name, fn counter ->
          new_counter = counter + 1
          {formatter_fn.(new_counter), new_counter}
        end)
      end
    end
    """

    confirm_fix(fix(input, @warning_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule HallucinatedAgentUpdateAnd do
      def next(agent_name, formatter_fn) do
        Agent.update_and(agent_name, fn counter ->
          new_counter = counter + 1
          {formatter_fn.(new_counter), new_counter}
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, @warning_message))
  end

  test "returns source unchanged when no Agent.update_and present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @warning_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def value(agent) do
        Agent.get(agent, & &1)
      end
    end
    """

    confirm_fix(fix(input, @warning_message), input)
  end
end
