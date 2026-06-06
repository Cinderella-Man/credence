defmodule Credence.Pattern.NoTrailingNewlineInDocEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic). Strips a trailing `\\n` from a `@doc`/`@moduledoc` string.
  `@doc` is compile-time documentation metadata; trimming a trailing newline
  changes neither runtime behaviour nor the dispatch of any function.
  """
  use ExUnit.Case, async: true
  import Credence.BehaviourEquivalence

  test "no_trailing_newline_in_doc: cosmetic — edits @doc text only, no runtime behaviour" do
    assert :ok =
             mark_equivalence_cosmetic(
               "Trims a trailing newline from a @doc/@moduledoc string — compile-time " <>
                 "documentation metadata, no effect on runtime behaviour."
             )
  end
end
