defmodule Credence.Pattern.NoBareValueInMapNewEquivalenceTest do
  @moduledoc """
  Repair rule (always-fails flavour). The rule fires ONLY on `Map.new(enum, fn x
  -> <non-pair literal> end)`, whose mapper returns a bare value (list, number,
  string, atom, map, non-2-tuple) instead of a `{key, value}` tuple. `Map.new/2`
  hands those to `:maps.from_list/1`, which raises `ArgumentError` on **every**
  non-empty enumerable — there is no input that produces a valid map. The fix
  pairs the element with the value (`fn k -> {k, value} end`), the canonical
  Map.new usage.

  So the "before" has no valid runtime behaviour to preserve; this is a
  correction, not a behaviour-preserving rewrite. See `mark_equivalence_repair/1`.
  """
  use Credence.RuleCase, async: true
  import Credence.BehaviourEquivalence

  test "no_bare_value_in_map_new: repair — bare-value Map.new mapper crashes on every input" do
    assert :ok =
             mark_equivalence_repair(
               "`Map.new(enum, fn _k -> [] end)` returns a bare value, not a {key, value} " <>
                 "tuple, so :maps.from_list/1 raises ArgumentError on EVERY non-empty enum — no " <>
                 "input produces a valid map. The rule matches ONLY provably-non-tuple literal " <>
                 "bodies (never a tuple, call, or variable that could be a pair), so it can fire " <>
                 "only on already-broken code. The fix `fn k -> {k, []} end` is the canonical Map.new."
             )
  end
end
