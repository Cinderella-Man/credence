defmodule Credence.Pattern.PreferFrequenciesOverGroupByEquivalenceTest do
  @moduledoc """
  `Enum.group_by(fn char -> char end) |> Enum.map(fn {_, v} -> length(v) end) |> Enum.count(fn c -> c > 1 end)`
  → `Enum.frequencies() |> Enum.count(fn {_, c} -> c > 1 end)`. Grouping each
  element by itself then counting group lengths produces the same frequency map
  as `Enum.frequencies/0`. Input set covers empty, no-duplicates, duplicates,
  and case-insensitive duplicates.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferFrequenciesOverGroupBy

  @before """
  defmodule Bad do
    def count_dupes(input) do
      input
      |> String.downcase()
      |> String.graphemes()
      |> Enum.group_by(fn char -> char end)
      |> Enum.map(fn {_key, values} -> length(values) end)
      |> Enum.count(fn count -> count > 1 end)
    end
  end
  """

  test "group_by(identity) |> map(length) |> count(>1) → frequencies |> count(>1) preserves behaviour" do
    assert_equivalent_module(@before,
      rule: PreferFrequenciesOverGroupBy,
      call: {:count_dupes, 1},
      inputs: ["", "abc", "aab", "aabb", "aA"]
    )
  end
end
