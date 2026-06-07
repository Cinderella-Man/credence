defmodule Credence.Pattern.NoListAppendInRecursionEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A tail-recursive accumulator that appends with `acc ++ [x]`
  (O(n²)) is rewritten to prepend `[x | acc]` and reverse at the base case — same
  output order, O(n). Input set covers empty and several elements.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListAppendInRecursion

  @before """
  defmodule Bad do
    def build([h | t], result), do: build(t, result ++ [h * 2])
    def build([], result), do: result
  end
  """

  test "acc ++ [x] recursion → prepend + reverse preserves the order" do
    assert_equivalent_module(@before,
      rule: NoListAppendInRecursion,
      call: {:build, 2},
      inputs: [{[], []}, {[1], []}, {[1, 2, 3], []}, {[-1, -2, -3], []}, {Enum.to_list(1..20), []}]
    )
  end
end
