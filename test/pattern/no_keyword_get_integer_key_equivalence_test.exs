defmodule Credence.Pattern.NoKeywordGetIntegerKeyEquivalenceTest do
  @moduledoc """
  Repair rule (always-fails flavour). `Keyword.get/2` is guarded `when is_atom(key)`,
  so `Keyword.get(list, <integer literal>)` raises `FunctionClauseError` on **every**
  input — verified exhaustively (6 list shapes × 4 integer keys = 24 combos, 0 of
  them produced a value). The rule fires only on integer *literals* in the 2-arg
  form (not variable/atom keys, not the 3-arg default form).

  The fix reinterprets the Python-index intent (`list[-1]`/`list[0]`/`list[n]`):
  `Keyword.get(v, -1)` → `List.last(v)`, `Keyword.get(v, 0)` → `List.first(v)`,
  `Keyword.get(v, n)` → `Enum.at(v, n)`. There is no valid before-behaviour to
  preserve — it always crashes — so this is a correction, not a behaviour-preserving
  rewrite. See `mark_equivalence_repair/1`.
  """
  use Credence.RuleCase, async: true
  import Credence.BehaviourEquivalence

  test "no_keyword_get_integer_key: repair — integer key to Keyword.get/2 crashes on every input" do
    assert :ok =
             mark_equivalence_repair(
               "`Keyword.get(list, <int literal>)` hits the `is_atom(key)` guard and raises " <>
                 "FunctionClauseError for EVERY list/key combination (24/24 probed crashed). " <>
                 "The fix maps the Python-index intent to List.last/List.first/Enum.at — no valid " <>
                 "before-behaviour exists to preserve."
             )
  end
end
