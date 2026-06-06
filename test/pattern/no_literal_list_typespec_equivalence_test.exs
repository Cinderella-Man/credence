defmodule Credence.Pattern.NoLiteralListTypespecEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic) — no runtime behaviour to compare.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoLiteralListTypespec

  # Firing snippets lifted from no_literal_list_typespec_check_test.exs:
  #   @spec foo(integer()) :: [pos_integer(), pos_integer()]
  #   @spec foo(integer()) :: [atom(), integer(), string()]
  #   @spec foo(integer()) :: [atom(), integer()]

  test "no_literal_list_typespec: cosmetic — provably no runtime behaviour to compare" do
    assert :ok = mark_equivalence_cosmetic("`@spec` is compile-only and the original does not even compile; no runtime behaviour to compare.")
  end
end
