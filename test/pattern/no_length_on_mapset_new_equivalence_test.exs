defmodule Credence.Pattern.NoLengthOnMapsetNewEquivalenceTest do
  @moduledoc """
  Repair rule — `length(MapSet.new(arg))` raises `ArgumentError` on every input
  (`length/1` only accepts lists, not `MapSet`s). There is no valid runtime
  behaviour to preserve; the fix is a correction, not a behaviour-preserving
  rewrite.
  """
  use Credence.RuleCase, async: true

  test "repair: length(MapSet.new(arg)) crashes on every input" do
    mark_equivalence_repair(
      "`length(MapSet.new(arg))` raises ArgumentError on every input " <>
        "(length/1 only accepts lists, not MapSets). ArgumentError 40/40 " <>
        "minimal_set=none."
    )
  end
end
