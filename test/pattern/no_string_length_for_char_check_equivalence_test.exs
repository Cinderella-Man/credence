defmodule Credence.Pattern.NoStringLengthForCharCheckEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoStringLengthForCharCheck

  # Firing snippets lifted from no_string_length_for_char_check_check_test.exs:
  #   defmodule GoodCheck do
  #       def count_char(string, <<_::utf8>> = target) do
  #         String.graphemes(string) |> Enum.count(&(&1 == target))
  #       end
  #     end
  #   defmodule BadCheck do
  #       def count_char(string, target_char) do
  #         if String.length(target_char) != 1 do
  #           raise ArgumentError, "target must be a single character"
  #         end
  #         String.graphemes(string) |> Enum.count(&(&1 == target_char))
  #       end
  #     end
  #   defmodule BadEq do
  #       def single_char?(s) do
  #         String.length(s) == 1
  #       end
  #     end

  test "no_string_length_for_char_check: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoStringLengthForCharCheck,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
