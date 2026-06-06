defmodule Credence.Pattern.NoPipedRegexReplaceEquivalenceTest do
  @moduledoc """
  Repair rule (always-fails flavour). The rule fires ONLY on the piped shape
  `value |> Regex.replace(~r/.../, replacement)`, which desugars to
  `Regex.replace(value, ~r/.../, replacement)` — putting `value` in
  `Regex.replace/3`'s *regex* slot. That raises `FunctionClauseError` on **every**
  input (verified: all strings, the empty string, and even a `%Regex{}` crash —
  there is no input that produces a valid result). The fix rewrites it to
  `value |> String.replace(~r/.../, replacement)`, the correct call.

  So the "before" has no valid runtime behaviour to preserve; this is a
  correction, not a behaviour-preserving rewrite. See `mark_equivalence_repair/1`.
  """
  use ExUnit.Case, async: true
  import Credence.BehaviourEquivalence

  test "no_piped_regex_replace: repair — piped `Regex.replace` arg-order bug crashes on every input" do
    assert :ok =
             mark_equivalence_repair(
               "`value |> Regex.replace(~r/../, repl)` = `Regex.replace(value, regex, repl)` puts " <>
                 "`value` in the regex slot, raising FunctionClauseError on EVERY input (strings, " <>
                 "empty string, even a %Regex{}). The fix `value |> String.replace(...)` is the " <>
                 "correct call — no valid before-behaviour exists to preserve."
             )
  end
end
