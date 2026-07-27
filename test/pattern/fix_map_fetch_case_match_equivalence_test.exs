defmodule Credence.Pattern.FixMapFetchCaseMatchEquivalenceTest do
  @moduledoc """
  Repair: the "before" code is broken on every successful `Map.fetch` — the bare
  map pattern `%{callers: callers} = info` never matches the `{:ok, value}` tuple
  that `Map.fetch/2` returns, so the `case` raises `CaseClauseError` on every
  successful fetch. The fix wraps the pattern in `{:ok, ...}`, which is the
  intended idiom. There is no input where the "before" produces a valid result
  from the success path, so behaviour-preservation is not testable.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  test "is a repair: bare map pattern never matches Map.fetch's {:ok, _} tuple" do
    mark_equivalence_repair(
      "Before code has a bare map pattern `%{callers: callers} = info` in a " <>
        "`case Map.fetch` success clause. `Map.fetch` returns `{:ok, value} | :error`, " <>
        "so the bare map pattern never matches the tuple — `CaseClauseError` on every " <>
        "successful fetch. The fix wraps in `{:ok, ...}`, correcting the bug."
    )
  end
end
