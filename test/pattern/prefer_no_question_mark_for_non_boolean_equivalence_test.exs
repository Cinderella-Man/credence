defmodule Credence.Pattern.PreferNoQuestionMarkForNonBooleanEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A function with `?` suffix whose `@spec` declares a
  non-boolean return type is renamed to drop the suffix. The rename is purely
  syntactic — the function body is unchanged, so the runtime behaviour is
  identical for every input.

  A wrapper function `f/1` delegates to the renamed function so both the
  before- and after-module expose the same call target for the harness.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferNoQuestionMarkForNonBoolean

  @before """
  defmodule Solution do
    @spec find_max_integer?([any()]) :: integer() | nil
    def find_max_integer?([]), do: nil

    def find_max_integer?(list) when is_list(list) do
      if Enum.any?(list, fn element -> not is_integer(element) end) do
        nil
      else
        Enum.max(list)
      end
    end

    def f(list), do: find_max_integer?(list)
  end
  """

  test "rename preserves runtime behaviour" do
    assert_equivalent_module(@before,
      rule: PreferNoQuestionMarkForNonBoolean,
      call: {:f, 1},
      inputs: [[], [1, 2, 3], [5, 1, 4], [42], [1, 1, 1], [-3, -1, -2]]
    )
  end
end
