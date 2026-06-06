defmodule Credence.Pattern.NoRepeatedDivRemEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRepeatedDivRem

  # Firing snippets lifted from no_repeated_div_rem_check_test.exs:
  #   defmodule Bad do
  #       defp check(x) do
  #         a = rem(x, 2)
  #         b = rem(x, 2)
  #         {a, b}
  #       end
  #     end
  #   defmodule Bad do
  #       defp f(x) when x < 5, do: x
  #     
  #       defp f(x) do
  #         new_x = div(x, 5)
  #         f(div(x, 5) + new_x)
  #       end
  #     end
  #   defmodule Bad do
  #       defp f(x) do
  #         q = div(x, 5)
  #         a = div(x, 5)
  #         b = div(x, 5)
  #         {q, a, b}
  #       end
  #     end

  test "no_repeated_div_rem: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoRepeatedDivRem,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
