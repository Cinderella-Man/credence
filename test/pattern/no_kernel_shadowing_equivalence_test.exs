defmodule Credence.Pattern.NoKernelShadowingEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoKernelShadowing

  # Firing snippets lifted from no_kernel_shadowing_check_test.exs:
  #   Enum.reduce(list, 0, fn x, max -> max(x, max) end)
  #   defmodule M do
  #       def f(list) do
  #         min = hd(list)
  #         min
  #       end
  #     end
  #   defmodule M do
  #       defp go([], max), do: max
  #     end

  test "no_kernel_shadowing: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoKernelShadowing,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
