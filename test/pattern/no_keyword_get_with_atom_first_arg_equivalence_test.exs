defmodule Credence.Pattern.NoKeywordGetWithAtomFirstArgEquivalenceTest do
  @moduledoc """
  Repair rule (always-fails flavour). `Keyword.get/2` and `Keyword.get/3`
  require a keyword list (a list of `{atom, value}` tuples) as the first
  argument. Passing an atom literal (e.g. `:clock`) as the first argument
  always raises `FunctionClauseError` because atoms are not keyword lists.

  The fix extracts the default value (the last argument), which is what the
  code intended to return. There is no valid before-behaviour to preserve —
  it always crashes. See `mark_equivalence_repair/1`.
  """
  use Credence.RuleCase, async: true
  import Credence.BehaviourEquivalence

  test "no_keyword_get_with_atom_first_arg: repair — atom first arg crashes on every input" do
    assert :ok =
             mark_equivalence_repair(
               "`Keyword.get(:atom, ...)` hits the keyword-list guard and raises " <>
                 "FunctionClauseError for EVERY atom/default combination. " <>
                 "The fix extracts the default (last argument) — no valid " <>
                 "before-behaviour exists to preserve."
             )
  end
end
