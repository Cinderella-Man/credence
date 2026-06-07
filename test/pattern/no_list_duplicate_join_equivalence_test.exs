defmodule Credence.Pattern.NoListDuplicateJoinEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `Enum.join(List.duplicate("=", n))` → `String.duplicate("=", n)`.
  Equivalent for every `n >= 0` (the natural domain of a duplicate count). A
  negative `n` is degenerate and raises in both forms — only the exception
  module differs (`FunctionClauseError` vs `ArgumentError`), so it is not
  asserted here.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListDuplicateJoin

  test "Enum.join(List.duplicate(s, n)) → String.duplicate(s, n) over n >= 0" do
    assert_equivalent(
      """
      Enum.join(List.duplicate("=", n))
      """,
      rule: NoListDuplicateJoin,
      vars: [:n],
      inputs: [0, 1, 3, 10, 100]
    )
  end
end
