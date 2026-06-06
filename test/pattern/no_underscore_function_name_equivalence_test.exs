defmodule Credence.Pattern.NoUnderscoreFunctionNameEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic). Renames a leading-underscore function (`_helper`) to a plain
  name and updates its in-module call sites. A whole-module consistent rename is
  behaviour-preserving for the computation — every call still resolves to the same
  body. (The function's name is the only observable that changes.)
  """
  use ExUnit.Case, async: true
  import Credence.BehaviourEquivalence

  test "no_underscore_function_name: cosmetic — whole-module function rename" do
    assert :ok =
             mark_equivalence_cosmetic(
               "Renames `_foo` to `foo` and rewrites in-module call sites — a consistent " <>
                 "rename; the computation at every call site is unchanged."
             )
  end
end
