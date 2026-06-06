defmodule Credence.Pattern.NoLiteralListTypespecEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic) — no runtime behaviour to compare.

  The rule only touches a `@spec`, which is compile-only metadata; the original
  (a literal-list spec) does not even compile, so no input can witness a
  difference between before and after.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence

  test "no_literal_list_typespec: cosmetic — provably no runtime behaviour to compare" do
    assert :ok =
             mark_equivalence_cosmetic(
               "`@spec` is compile-only and the original does not even compile; no runtime behaviour to compare."
             )
  end
end
