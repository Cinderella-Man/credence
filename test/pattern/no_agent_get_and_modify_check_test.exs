defmodule Credence.Pattern.NoAgentGetAndModifyCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoAgentGetAndModify

  describe "flags Agent.get_and_modify" do
    test "standalone call" do
      code = """
      defmodule M do
        def update_state do
          Agent.get_and_modify(__MODULE__, fn state ->
            {state.count, %{state | count: state.count + 1}}
          end)
        end
      end
      """

      assert [%Issue{rule: :no_agent_get_and_modify}] = check(NoAgentGetAndModify, code)
    end

    test "with named agent" do
      assert [%Issue{rule: :no_agent_get_and_modify}] =
               check(NoAgentGetAndModify, "Agent.get_and_modify(:my_agent, fn s -> {s, s} end)")
    end

    test "piped call" do
      code = "__MODULE__ |> Agent.get_and_modify(fn s -> {s, s} end)"

      assert [%Issue{rule: :no_agent_get_and_modify}] = check(NoAgentGetAndModify, code)
    end

    test "call with explicit timeout argument" do
      code = "Agent.get_and_modify(pid, fn s -> {s, s} end, 10_000)"

      assert [%Issue{rule: :no_agent_get_and_modify}] = check(NoAgentGetAndModify, code)
    end

    test "function capture" do
      assert [%Issue{rule: :no_agent_get_and_modify}] =
               check(NoAgentGetAndModify, "&Agent.get_and_modify/2")
    end
  end

  describe "leaves correct code alone" do
    test "Agent.get_and_update is not flagged" do
      code = """
      defmodule M do
        def update_state do
          Agent.get_and_update(__MODULE__, fn state ->
            {state.count, %{state | count: state.count + 1}}
          end)
        end
      end
      """

      assert clean?(NoAgentGetAndModify, code)
    end

    test "other Agent functions are not flagged" do
      code = """
      defmodule M do
        def get_state, do: Agent.get(__MODULE__, & &1)
        def stop, do: Agent.stop(__MODULE__)
      end
      """

      assert clean?(NoAgentGetAndModify, code)
    end

    test "get_and_modify on a user module is not flagged" do
      code = "MyApp.Agent.get_and_modify(pid, fn s -> {s, s} end)"

      assert clean?(NoAgentGetAndModify, code)
    end

    test "get_and_modify on a variable receiver is not flagged" do
      code = """
      mod = Agent
      mod.get_and_modify(pid, fn s -> {s, s} end)
      """

      assert clean?(NoAgentGetAndModify, code)
    end
  end
end
