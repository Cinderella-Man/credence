defmodule Credence.Pattern.NoRecursiveCaseWithoutEmptyListClauseEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `case stack do [top | rest] -> ... end` with no `[]`
  clause crashes on empty lists. The fix adds `[] -> {[], MapSet.new()}` which
  handles the empty case. For non-empty list inputs, both before and after
  produce the same result — the added `[]` clause is never reached.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRecursiveCaseWithoutEmptyListClause

  @before """
  defmodule Solution do
    def pop_larger_chars_helper(stack, seen, char, counts) do
      case stack do
        [top | rest] ->
          remaining = Map.get(counts, top, 0)

          if top > char and remaining > 0 do
            new_seen = MapSet.delete(seen, top)
            pop_larger_chars_helper(rest, new_seen, char, counts)
          else
            {stack, seen}
          end
      end
    end
  end
  """

  test "fix preserves behaviour for non-empty list inputs" do
    assert_equivalent_module(@before,
      rule: NoRecursiveCaseWithoutEmptyListClause,
      call: {:pop_larger_chars_helper, 4},
      inputs: [
        # No recursion: top <= char, returns immediately
        {[?a], MapSet.new([?a]), ?b, %{?a => 1}},
        # No recursion: remaining = 0, returns immediately
        {[?b], MapSet.new([?b]), ?a, %{?b => 0}},
        # No recursion: top <= char on first element
        {[?a, ?b], MapSet.new([?a, ?b]), ?c, %{?a => 1, ?b => 1}},
        # Recursion: pops ?c then stops at ?a (97 <= 98)
        {[?c, ?a], MapSet.new([?c, ?a]), ?b, %{?c => 1, ?a => 1}}
      ]
    )
  end
end
