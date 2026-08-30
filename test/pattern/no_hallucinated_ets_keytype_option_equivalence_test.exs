defmodule Credence.Pattern.NoHallucinatedEtsKeytypeOptionEquivalenceTest do
  @moduledoc """
  Repair rule — `keytype: :term` is not an `:ets.new/2` option, so Erlang
  rejects the entire option list and the call raises `ArgumentError` on every
  input. There is no valid runtime behaviour to preserve; the fix is a
  correction.
  """
  use Credence.RuleCase, async: true

  test "repair: :ets.new/2 rejects the invented option on every input" do
    mark_equivalence_repair(
      "`keytype: :term` does not exist in Erlang's ETS. `:ets.new/2` validates " <>
        "its whole option list and raises ArgumentError (\"2nd argument: invalid " <>
        "options\") for every input, so no table is ever created and there is no " <>
        "behaviour to preserve. The fix removes the invented pair and leaves the " <>
        "real options, which is the table the author meant to create."
    )
  end
end
