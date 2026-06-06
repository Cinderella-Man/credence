defmodule Credence.Pattern.PreferHeredocForMultiLineDocEquivalenceTest do
  @moduledoc """
  Tier 3a (cosmetic). Rewrites a multi-line `@doc "...\\n..."` string into heredoc
  syntax. This changes only the *source representation* of compile-time doc
  metadata (the string value is equivalent); no runtime behaviour is affected.
  """
  use ExUnit.Case, async: true
  import Credence.BehaviourEquivalence

  test "prefer_heredoc_for_multi_line_doc: cosmetic — doc source representation only" do
    assert :ok =
             mark_equivalence_cosmetic(
               "Converts a \\n-escaped @doc string to heredoc syntax — source-representation " <>
                 "change to compile-time documentation, no runtime behaviour impact."
             )
  end
end
