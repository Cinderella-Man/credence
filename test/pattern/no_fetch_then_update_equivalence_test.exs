defmodule Credence.Pattern.NoFetchThenUpdateEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). A `case Map.fetch(map, key)` that increments on `{:ok, n}`
  and inserts on `:error`, returning `{old, updated_map}`. The fix rewrites the
  `{:ok, n}` branch's `Map.update!` to the equivalent direct put. Battery covers
  key present (int/float value) and absent.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoFetchThenUpdate

  @expr """
  case Map.fetch(counts, key) do
    {:ok, n} -> {n, Map.update!(counts, key, &(&1 + 1))}
    :error -> {0, Map.put(counts, key, 1)}
  end
  """

  test "fetch-then-update preserves the {old, updated_map} result" do
    assert_equivalent(@expr,
      rule: NoFetchThenUpdate,
      vars: [:counts, :key],
      inputs: [{%{}, :a}, {%{a: 1}, :a}, {%{a: 1.0}, :a}, {%{a: 1, b: 2}, :b}, {%{"k" => 5}, "k"}]
    )
  end
end
