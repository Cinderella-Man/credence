defmodule Credence.Pattern.NoManualFindEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A manual `find([h|_]) when pred -> h; find([_|t]) -> recurse;
  find([]) -> default` collapses to `Enum.find/2` (with the default preserved).
  `is_list/1` holds for improper lists too, so the rewrite keeps the exact domain.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualFind

  @before """
  defmodule Bad do
    def find(l), do: find_positive(l)
    defp find_positive([]), do: -1
    defp find_positive([h | _t]) when h > 0, do: h
    defp find_positive([_h | t]), do: find_positive(t)
  end
  """

  test "manual find recursion → Enum.find preserves the first match and default" do
    assert_equivalent_module(@before,
      rule: NoManualFind,
      call: {:find, 1},
      inputs: [[], [1, 2], [-1, -2, 3], [-1, -2], [0, 0, 5]]
    )
  end
end
