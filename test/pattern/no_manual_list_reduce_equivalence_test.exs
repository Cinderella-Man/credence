defmodule Credence.Pattern.NoManualListReduceEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualListReduce

  # Firing snippets lifted from no_manual_list_reduce_check_test.exs:
  #   defmodule Good do
  #       defp f([], acc), do: acc
  #       defp f([h | t], acc), do: f(t, acc ++ [h | t])
  #     end
  #   defmodule Good do
  #       defp f([], acc), do: acc
  #       defp f([h | t], acc) do
  #         IO.inspect(h)
  #         f(t, acc + h)
  #       end
  #     end
  #   defmodule Good do
  #       defp f([], acc), do: acc
  #       defp f([acc | t], acc), do: f(t, acc)
  #     end

  test "no_manual_list_reduce: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoManualListReduce,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
