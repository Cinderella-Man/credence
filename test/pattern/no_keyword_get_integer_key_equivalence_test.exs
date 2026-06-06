defmodule Credence.Pattern.NoKeywordGetIntegerKeyEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoKeywordGetIntegerKey

  # Firing snippets lifted from no_keyword_get_integer_key_check_test.exs:
  #   Keyword.get(acc, -1)
  #   defmodule E do
  #       def first(l), do: Keyword.get(l, 0)
  #       def last(l), do: Keyword.get(l, -1)
  #     end
  #   prev = Keyword.get(acc, -1)

  test "no_keyword_get_integer_key: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoKeywordGetIntegerKey,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
