defmodule Credence.Pattern.NoManualStringReverseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoManualStringReverse

  # Firing snippets lifted from no_manual_string_reverse_check_test.exs:
  #   defmodule BadPalindrome do
  #       def is_palindrome(word) do
  #         normalized = String.downcase(word)
  #         reversed = normalized |> String.graphemes() |> Enum.reverse() |> Enum.join()
  #         normalized == reversed
  #       end
  #     end
  #   defmodule BadNested do
  #       def reverse_string(s) do
  #         Enum.join(Enum.reverse(String.graphemes(s)))
  #       end
  #     end
  #   defmodule Example do
  #       def reverse(str) do
  #         str
  #         |> String.trim()
  #         |> String.graphemes()
  #         |> Enum.reverse()
  #         |> Enum.join()
  #       end
  #     end

  test "no_manual_string_reverse: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoManualStringReverse,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
