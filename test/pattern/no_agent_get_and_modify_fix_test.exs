defmodule Credence.Pattern.NoAgentGetAndModifyFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoAgentGetAndModify

  describe "rewrites Agent.get_and_modify to Agent.get_and_update" do
    test "standalone call" do
      input = ~S"""
      Agent.get_and_modify(__MODULE__, fn state ->
        new_state = %{state | count: state.count + 1}
        {state.count, new_state}
      end)
      """

      expected = ~S"""
      Agent.get_and_update(__MODULE__, fn state ->
        new_state = %{state | count: state.count + 1}
        {state.count, new_state}
      end)
      """

      confirm_fix(fix(NoAgentGetAndModify, input), expected)
    end

    test "inside a module" do
      input = ~S"""
      defmodule HallucinatedAgentCall do
        def update_state do
          Agent.start_link(fn -> %{count: 0} end, name: __MODULE__)

          Agent.get_and_modify(__MODULE__, fn state ->
            new_state = %{state | count: state.count + 1}
            {state.count, new_state}
          end)
        end
      end
      """

      expected = ~S"""
      defmodule HallucinatedAgentCall do
        def update_state do
          Agent.start_link(fn -> %{count: 0} end, name: __MODULE__)

          Agent.get_and_update(__MODULE__, fn state ->
            new_state = %{state | count: state.count + 1}
            {state.count, new_state}
          end)
        end
      end
      """

      confirm_fix(fix(NoAgentGetAndModify, input), expected)
    end
  end

  describe "no-ops" do
    test "Agent.get_and_update is unchanged" do
      code = ~S"""
      Agent.get_and_update(__MODULE__, fn state ->
        {state, state}
      end)
      """

      confirm_fix(fix(NoAgentGetAndModify, code), code)
    end

    test "other Agent functions are unchanged" do
      code = "Agent.get(__MODULE__, &(&1))"
      confirm_fix(fix(NoAgentGetAndModify, code), code)
    end
  end
end
