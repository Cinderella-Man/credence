defmodule Credence.Pattern.PreferEnumFrequenciesOverGroupByEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call).
  `Enum.group_by(list, & &1) |> Map.new(fn {k, v} -> {k, length(v)} end)` →
  `Enum.frequencies(list)`. Grouping by identity then taking each group's length
  is exactly a frequency count. Input set covers duplicates, empty, mixed types.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferEnumFrequenciesOverGroupBy

  @before """
  defmodule FrequencyExample do
    def count_items(list) do
      Enum.group_by(list, & &1) |> Map.new(fn {k, v} -> {k, length(v)} end)
    end
  end
  """

  @before_into """
  defmodule FrequencyExample do
    def count_items(list) do
      Enum.group_by(list, & &1) |> Enum.into(%{}, fn {k, v} -> {k, length(v)} end)
    end
  end
  """

  test "group_by(& &1) |> Map.new(length) → Enum.frequencies preserves the counts" do
    assert_equivalent_module(@before,
      rule: PreferEnumFrequenciesOverGroupBy,
      call: {:count_items, 1},
      inputs: Credence.EquivalenceInputs.term_lists()
    )
  end

  test "group_by(& &1) |> Enum.into(%{}, length) → Enum.frequencies preserves the counts" do
    assert_equivalent_module(@before_into,
      rule: PreferEnumFrequenciesOverGroupBy,
      call: {:count_items, 1},
      inputs: Credence.EquivalenceInputs.term_lists()
    )
  end
end
