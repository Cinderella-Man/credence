defmodule Credence.Pattern.NoAgentGetAndModifyEquivalenceTest do
  @moduledoc """
  Repair case: `Agent.get_and_modify/2` does not exist in Elixir when `Agent`
  names the standard library module. The fix replaces it with the real
  `Agent.get_and_update/2`, but leaves calls alone when `Agent` is aliased.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  alias Credence.Pattern.NoAgentGetAndModify
  alias Credence.RuleHelpers

  test "repair — built-in Agent.get_and_modify/2 does not exist" do
    assert :ok =
             mark_equivalence_repair(
               "`Agent.get_and_modify/2` does not exist in Elixir's built-in Agent module — " <>
                 "the call always raises `UndefinedFunctionError`. The fix replaces it " <>
                 "with the real `Agent.get_and_update/2` (identical semantics)."
             )
  end

  test "does not repair Agent when it aliases a user-defined module" do
    source = ~S"""
    defmodule AliasTargetNagamEquivalence do
      def get_and_modify(_pid, _fun), do: :original
      def get_and_update(_pid, _fun), do: :rewritten
    end

    alias AliasTargetNagamEquivalence, as: Agent

    unless Agent.get_and_modify(:pid, fn state -> {state, state} end) == :original do
      raise "aliased call changed"
    end
    """

    emitted = fix(NoAgentGetAndModify, source)

    assert [] == check(NoAgentGetAndModify, source)
    confirm_fix(emitted, source)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(source)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(emitted)
  end
end
