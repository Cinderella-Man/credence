defmodule Credence.Pattern.PreferRegexMatchEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `case Regex.run(re, s) do [_ | _] -> a; nil -> b end` → `if Regex.match?(re, s), do: a, else: b`.
  `Regex.run` returns a non-empty list (matched) or nil (no match), exactly the
  boolean `Regex.match?`. Input set covers match, no-match, and empty string.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferRegexMatch

  @expr """
  case Regex.run(~r/ab+/, s) do
    [_ | _] -> :yes
    nil -> :no
  end
  """

  test "case Regex.run → if Regex.match? preserves the branch" do
    assert_equivalent(@expr,
      rule: PreferRegexMatch,
      vars: [:s],
      inputs: ["abbb", "xyz", "", "ab", "zzab"]
    )
  end
end
