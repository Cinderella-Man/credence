defmodule Credence.Pattern.PreferPatternMatchEmptyStringEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `def f(str, c) when byte_size(str) == 0` →
  `def f("" = str, c)`. An empty string is exactly the strings for which
  `byte_size(str) == 0`, so the pattern selects exactly the same inputs;
  non-empty strings still fall through to the next clause.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferPatternMatchEmptyString

  @before """
  defmodule ReverseLeftWords do
    def reverse_left_words(str, _count) when byte_size(str) == 0, do: str
    def reverse_left_words(str, count) do
      len = String.length(str)
      actual_count = rem(count, len)
      {left, right} = String.split_at(str, actual_count)
      right <> left
    end
  end
  """

  test "byte_size(str) == 0 guard → \"\" pattern preserves dispatch" do
    assert_equivalent_module(@before,
      rule: PreferPatternMatchEmptyString,
      call: {:reverse_left_words, 2},
      inputs: [
        {"", 0},
        {"", 5},
        {"hello", 2},
        {"abc", 3},
        {"", -1},
        {"world", 7}
      ]
    )
  end
end
