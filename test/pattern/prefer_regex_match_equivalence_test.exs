defmodule Credence.Pattern.PreferRegexMatchEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.PreferRegexMatch

  # Firing snippets lifted from prefer_regex_match_check_test.exs:
  #   defmodule M do
  #       def match?(s) do
  #         case Regex.run(~r/ab{3,}/, s) do
  #           [_ | _] -> "Found a match!"
  #           _ -> "Not matched!"
  #         end
  #       end
  #     end
  #   defmodule M do
  #       def match?(s) do
  #         case Regex.run(~r/\d+/, s) do
  #           [_ | _] -> :found
  #           nil -> :not_found
  #         end
  #       end
  #     end
  #   defmodule M do
  #       def match?(s) do
  #         case Regex.run(~r/[a-z]+/, s) do
  #           nil -> :no
  #           [_ | _] -> :yes
  #         end
  #       end
  #     end

  test "prefer_regex_match: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: PreferRegexMatch,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
