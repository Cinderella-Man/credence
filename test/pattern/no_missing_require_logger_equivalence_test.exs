defmodule Credence.Pattern.NoMissingRequireLoggerEquivalenceTest do
  @moduledoc """
  Tier 3b (unconstructible). Adds a missing `require Logger` to a module that calls
  Logger macros. `Logger.info/2` etc. are macros that require `require Logger`; a
  module that calls them WITHOUT the require does not compile. So there is no
  runnable "before" to compare against — the fix makes invalid code compile.
  """
  use Credence.RuleCase, async: true
  import Credence.BehaviourEquivalence

  test "no_missing_require_logger: unconstructible — module without the require does not compile" do
    assert :ok =
             mark_equivalence_unconstructible(
               "The rule fires when a module uses Logger macros but is missing `require Logger`; " <>
                 "such a module does not compile, so there is no runnable before-code to compare."
             )
  end
end
