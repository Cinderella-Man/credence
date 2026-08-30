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

    test "piped call" do
      input = ~S"""
      __MODULE__ |> Agent.get_and_modify(fn state -> {state, state} end)
      """

      expected = ~S"""
      __MODULE__ |> Agent.get_and_update(fn state -> {state, state} end)
      """

      confirm_fix(fix(NoAgentGetAndModify, input), expected)
    end

    test "call with explicit timeout argument" do
      input = ~S"""
      Agent.get_and_modify(pid, fn state -> {state, state} end, 10_000)
      """

      expected = ~S"""
      Agent.get_and_update(pid, fn state -> {state, state} end, 10_000)
      """

      confirm_fix(fix(NoAgentGetAndModify, input), expected)
    end

    test "function capture" do
      input = ~S"""
      Enum.map(agents, &Agent.get_and_modify(&1, fn s -> {s, s} end))
      """

      expected = ~S"""
      Enum.map(agents, &Agent.get_and_update(&1, fn s -> {s, s} end))
      """

      confirm_fix(fix(NoAgentGetAndModify, input), expected)
    end

    test "arity capture" do
      input = ~S"""
      &Agent.get_and_modify/2
      """

      expected = ~S"""
      &Agent.get_and_update/2
      """

      confirm_fix(fix(NoAgentGetAndModify, input), expected)
    end

    test "quoted identifier" do
      input = ~S"""
      Agent."get_and_modify"(pid, fn s -> {s, s} end)
      """

      expected = ~S"""
      Agent.get_and_update(pid, fn s -> {s, s} end)
      """

      confirm_fix(fix(NoAgentGetAndModify, input), expected)
    end

    test "identifier on its own line" do
      input = ~S"""
      Agent.
        get_and_modify(pid, fn s -> {s, s} end)
      """

      expected = ~S"""
      Agent.
        get_and_update(pid, fn s -> {s, s} end)
      """

      confirm_fix(fix(NoAgentGetAndModify, input), expected)
    end

    test "surrounding comments are preserved" do
      input = ~S"""
      # bump the counter
      Agent.get_and_modify(__MODULE__, fn state ->
        # reply with the old count
        {state.count, %{state | count: state.count + 1}}
      end)
      """

      expected = ~S"""
      # bump the counter
      Agent.get_and_update(__MODULE__, fn state ->
        # reply with the old count
        {state.count, %{state | count: state.count + 1}}
      end)
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

    test "get_and_modify on a user module is unchanged" do
      code = ~S"""
      MyApp.Agent.get_and_modify(pid, fn s -> {s, s} end)
      """

      confirm_fix(fix(NoAgentGetAndModify, code), code)
    end

    test "get_and_modify on a variable receiver is unchanged" do
      code = ~S"""
      mod = Agent
      mod.get_and_modify(pid, fn s -> {s, s} end)
      """

      confirm_fix(fix(NoAgentGetAndModify, code), code)
    end
  end
end
