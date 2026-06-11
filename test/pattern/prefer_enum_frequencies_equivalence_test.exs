defmodule Credence.Pattern.PreferEnumFrequenciesEquivalenceTest do
  @moduledoc """
  `Enum.group_by(fn x -> x end, fn x -> x end)
   |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
   |> Enum.sort |> Enum.take(k) |> Enum.map(&elem(&1, 0))`
  → `Enum.frequencies() |> Enum.sort |> Enum.take(k) |> Enum.map(&elem(&1, 0))`.

  The downstream steps (sort, take, map) erase the type difference between the
  list-of-tuples output of group_by |> map and the map output of Enum.frequencies.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferEnumFrequencies

  @before """
  defmodule FrequencyExample do
    def top_k(nums, k) do
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      |> Enum.take(k)
      |> Enum.map(&elem(&1, 0))
    end
  end
  """

  test "full pipeline with group_by(identity,identity) |> map(count) → Enum.frequencies preserves behaviour" do
    assert_equivalent_module(@before,
      rule: PreferEnumFrequencies,
      call: {:top_k, 2},
      inputs: Enum.map(Credence.EquivalenceInputs.term_lists(), fn list -> {list, 3} end)
    )
  end
end
