defmodule Credence.Pattern.HallucinatedGuardEquivalenceTest do
  @moduledoc """
  Tier 3b (unconstructible). The rule replaces a hallucinated (non-existent) guard
  like `is_pos_integer(x)` with a real expansion (`is_integer(x) and x > 0`). The
  original never compiles — a hallucinated guard is an undefined macro — so there
  is no runnable "before" to compare against. No behaviour-equivalence battery
  applies; the value is making invalid code compile.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence

  test "hallucinated_guard: unconstructible — original (undefined guard) does not compile" do
    assert :ok =
             mark_equivalence_unconstructible(
               "Original uses a hallucinated guard (e.g. `is_pos_integer/1`) that is an undefined " <>
                 "macro and does not compile — no runnable before-code to compare."
             )
  end
end
