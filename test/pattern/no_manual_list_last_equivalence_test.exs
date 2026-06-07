defmodule Credence.Pattern.NoManualListLastEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A hand-rolled last-element recursion (`f([val]) -> val`,
  `f([_|rest]) -> f(rest)`) is rewritten to `hd(Enum.reverse(list))`.

  On any NON-EMPTY list both return the last element. On `[]` both *raise* (the
  manual form has no `[]` clause → `FunctionClauseError`; `hd(Enum.reverse([]))` →
  `ArgumentError`) — an error-type-only difference on the degenerate input, which
  is why the fix uses `hd(Enum.reverse/1)` rather than `List.last/1` (the latter
  would silently return `nil` on `[]`, a real behaviour change). The input set uses
  non-empty lists to pin the value-preserving domain.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualListLast

  @before """
  defmodule Bad do
    def last(l), do: get_last(l)
    defp get_last([val]), do: val
    defp get_last([_ | rest]), do: get_last(rest)
  end
  """

  test "manual last-element recursion → hd(Enum.reverse/1) preserves the last element" do
    assert_equivalent_module(@before,
      rule: NoManualListLast,
      call: {:last, 1},
      inputs: [[1], [1, 2, 3], [:a, :b, :c], [nil], Enum.to_list(1..50)]
    )
  end
end
