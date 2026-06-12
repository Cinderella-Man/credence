defmodule Credence.Pattern.PreferComprehensionForFilteredRangeEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `Enum.reduce/3` with accumulator prepend + `Enum.reverse/1`
  over a range → `for` comprehension with guard. Both produce the same list of
  missing numbers for every input shape: empty, complete, partial, with dupes.
  """
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferComprehensionForFilteredRange

  @before_code """
  defmodule FindMissing do
    def findmissingnumbers(numbers) do
      n = length(numbers)
      present = MapSet.new(numbers)

      Enum.reduce(1..n, [], fn num, missing ->
        if MapSet.member?(present, num), do: missing, else: [num | missing]
      end)
      |> Enum.reverse()
    end
  end
  """

  test "fix preserves behaviour across diverse inputs" do
    assert_equivalent_module(@before_code,
      rule: PreferComprehensionForFilteredRange,
      call: {:findmissingnumbers, 1},
      inputs: [
        # empty list
        [],
        # single element, no missing
        [1],
        # single element, missing 1
        [2],
        # no missing numbers
        [1, 2, 3, 4, 5],
        # all missing except last
        [5],
        # some missing, ascending
        [1, 3, 5],
        # some missing, unsorted with dupes
        [3, 1, 3, 5, 1],
        # all missing (empty present)
        [],
        # larger input
        Enum.to_list(1..50) |> Enum.reject(&(rem(&1, 3) == 0))
      ]
    )
  end
end
