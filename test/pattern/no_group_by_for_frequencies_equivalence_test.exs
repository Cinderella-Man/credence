defmodule Credence.Pattern.NoGroupByForFrequenciesEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call).
  `words |> Enum.group_by(f) |> Map.new(fn {k, group} -> {k, length(group)} end)` →
  `Enum.frequencies_by(words, f)`. Grouping then taking each group's length is
  exactly a frequency count keyed by `f`. Input set covers duplicates and empty.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoGroupByForFrequencies

  @before """
  defmodule Bad do
    def freq(words) do
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
    end
  end
  """

  test "group_by |> Map.new(length) → Enum.frequencies_by preserves the counts" do
    assert_equivalent_module(@before,
      rule: NoGroupByForFrequencies,
      call: {:freq, 1},
      inputs: [[], ["a", "A", "b"], ["x", "x", "x"], ["Cat", "cat", "Dog"]]
    )
  end
end
