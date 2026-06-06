defmodule Credence.Pattern.NoAttrBeforeDefmoduleEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic). Moves documentation/spec module attributes that sit *before*
  a `defmodule` to inside it. `@doc`/`@moduledoc`/`@spec` are compile-time metadata;
  relocating them attaches the docs to the module but does not change any function's
  runtime behaviour or dispatch.
  """
  use ExUnit.Case, async: true
  import Credence.BehaviourEquivalence

  test "no_attr_before_defmodule: cosmetic — relocates doc/spec metadata, no runtime behaviour" do
    assert :ok =
             mark_equivalence_cosmetic(
               "Moves doc/spec attributes from before a defmodule to inside it — compile-time " <>
                 "metadata placement, no runtime behaviour change."
             )
  end
end
