defmodule Credence.Pattern.InconsistentParamNamesEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.InconsistentParamNames

  # Firing snippets lifted from inconsistent_param_names_check_test.exs:
  #   defmodule Server do
  #       @impl true
  #       def handle_call(:get, _from, state), do: {:reply, state, state}
  #     
  #       @impl true
  #       def handle_call(:reset, _from, server_state), do: {:reply, :ok, server_state}
  #     end
  #   defmodule Math do
  #       @doc "positive"
  #       def sign(n) when n > 0, do: 1
  #     
  #       @doc "negative"
  #       def sign(num) when num < 0, do: -1
  #     end
  #   defmodule Mixed do
  #       @doc "first"
  #       @spec f(integer()) :: integer()
  #       @impl true
  #       def f(num), do: num + 1
  #     
  #       @doc "second"
  #       @impl true
  #       def f(n) when n > 100, do: n * 2
  #     end

  test "inconsistent_param_names: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: InconsistentParamNames,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
