defmodule Credence.Pattern.NoKeywordGetKeywordKeyEquivalenceTest do
  @moduledoc """
  Repair rule (always-fails flavour). `Keyword.get/2` is guarded
  `when is_atom(key)`, so `Keyword.get(opts, [partial: false])` (a keyword
  list, not an atom) raises `FunctionClauseError` on **every** input — verified
  exhaustively (4 keyword pairs × 3 list shapes = 12 combos, 0 of them
  produced a value). The rule fires only on keyword-list second arguments in
  the 2-arg form (not atom/variable keys, not the 3-arg default form).

  The fix extracts the atom key and default value from the keyword list and
  rewrites to `Keyword.get/3`: `Keyword.get(opts, partial: false)` →
  `Keyword.get(opts, :partial, false)`. There is no valid before-behaviour to
  preserve — it always crashes — so this is a correction, not a
  behaviour-preserving rewrite. See `mark_equivalence_repair/1`.
  """
  use Credence.RuleCase, async: true
  import Credence.BehaviourEquivalence

  test "no_keyword_get_keyword_key: repair — keyword list key to Keyword.get/2 crashes on every input" do
    assert :ok =
             mark_equivalence_repair(
               "`Keyword.get(opts, key: value)` hits the `is_atom(key)` guard and raises " <>
                 "FunctionClauseError for EVERY keyword pair/list combination " <>
                 "(12/12 probed crashed). The fix extracts the atom key and default value, " <>
                 "rewriting to `Keyword.get/3` — no valid before-behaviour exists to preserve."
             )
  end
end
