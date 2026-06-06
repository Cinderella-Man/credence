defmodule Credence.Pattern.NoRedundantBinarySyntaxEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoRedundantBinarySyntax

  # Firing snippets lifted from no_redundant_binary_syntax_check_test.exs:
  #   <<"hello">>
  #   defmodule E do
  #       def f, do: <<"a">>
  #       def g, do: <<"b">>
  #     end
  #   [<<"b">>, <<"a">>, <<"n">>]

  test "no_redundant_binary_syntax: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoRedundantBinarySyntax,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
