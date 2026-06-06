defmodule Credence.Pattern.NoUnnecessaryCatchAllRaiseEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Removes a redundant catch-all clause whose only job is to
  `raise` for inputs the earlier clauses already exclude. On the in-domain inputs
  (here, lists) dispatch is unchanged. The only difference is on out-of-domain input
  (a non-list): the explicit `raise ArgumentError` becomes the natural
  `FunctionClauseError` — both raise, an error-type-only difference outside the
  function's domain. The battery pins the in-domain (list) behaviour.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoUnnecessaryCatchAllRaise

  @before """
  defmodule Bad do
    def missing_number([]), do: 0
    def missing_number(nums) when is_list(nums), do: length(nums)
    def missing_number(_), do: raise(ArgumentError, "expected a list")
  end
  """

  test "dropping the redundant catch-all raise preserves the in-domain (list) behaviour" do
    assert_equivalent_module(@before,
      rule: NoUnnecessaryCatchAllRaise,
      call: {:missing_number, 1},
      inputs: [[], [1, 2, 3], [:a, :b], [nil], Enum.to_list(1..10)]
    )
  end
end
