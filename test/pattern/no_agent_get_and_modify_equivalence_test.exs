defmodule Credence.Pattern.NoAgentGetAndModifyEquivalenceTest do
  @moduledoc """
  Repair case: `Agent.get_and_modify/2` does not exist in Elixir — the
  original code always raises `UndefinedFunctionError` on every input.
  The fix replaces it with the real `Agent.get_and_update/2`.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "repair — Agent.get_and_modify/2 does not exist, always raises" do
    assert :ok =
             mark_equivalence_repair(
               "`Agent.get_and_modify/2` does not exist in Elixir's Agent module — " <>
                 "the call always raises `UndefinedFunctionError`. The fix replaces it " <>
                 "with the real `Agent.get_and_update/2` (identical semantics)."
             )
  end
end
