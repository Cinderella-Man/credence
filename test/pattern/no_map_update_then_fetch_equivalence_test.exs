defmodule Credence.Pattern.NoMapUpdateThenFetchEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `map = Map.update(map, key, init, fun); val = Map.fetch!(map, key)`
  → computes `val` from the update directly (the just-updated key's value is known),
  dropping the redundant re-fetch. Input set covers key absent (uses `init`) and
  present (applies `fun`), incl. a value-kind value.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMapUpdateThenFetch

  @before """
  defmodule Bad do
    def inc(map, key) do
      map = Map.update(map, key, 1, &(&1 + 1))
      val = Map.fetch!(map, key)
      {map, val}
    end
  end
  """

  test "update-then-fetch! → direct value preserves {map, val}" do
    assert_equivalent_module(@before,
      rule: NoMapUpdateThenFetch,
      call: {:inc, 2},
      inputs: [{%{}, :a}, {%{a: 1}, :a}, {%{a: 1.0}, :a}, {%{b: 2}, :a}, {%{"k" => 5}, "k"}]
    )
  end
end
