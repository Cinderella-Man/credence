defmodule Credence.Pattern.NoCryptoHashPipeSwappedArgsEquivalenceTest do
  @moduledoc """
  Repair rule — `data |> :crypto.hash(:sha256)` is `:crypto.hash(data,
  :sha256)`, which raises `ArgumentError` on every input: the first argument is
  not a hash algorithm and the second is not an iodata term. There is no valid
  runtime behaviour to preserve; the fix is a correction.
  """
  use Credence.RuleCase, async: true

  test "repair: the piped form raises ArgumentError on every input" do
    mark_equivalence_repair(
      "`data |> :crypto.hash(:sha256)` expands to `:crypto.hash(data, :sha256)`, " <>
        "which swaps the arguments :crypto.hash/2 takes. Erlang rejects it for " <>
        "every input — the algorithm position holds the data and the data " <>
        "position holds an atom, so the call raises ArgumentError before " <>
        "producing any value. The fix restores the documented order, " <>
        ":crypto.hash(algorithm, data)."
    )
  end
end
