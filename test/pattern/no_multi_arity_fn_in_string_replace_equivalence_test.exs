defmodule Credence.Pattern.NoMultiArityFnInStringReplaceEquivalenceTest do
  @moduledoc """
  Repair rule. `String.replace/3` only accepts arity-1 function replacements
  (guard: `is_function(replacement, 1)`), so passing a multi-arity callback
  always crashes at runtime with `FunctionClauseError` on EVERY input. There
  is no valid runtime behaviour to preserve — the fix rewrites to
  `Regex.replace/3`, which natively supports multi-arity callbacks.
  """
  use Credence.RuleCase, async: true

  test "repair: String.replace with multi-arity fn crashes on every input" do
    assert :ok =
             mark_equivalence_repair(
               "`String.replace/3` only accepts arity-1 function replacements " <>
                 "(guard: `is_function(replacement, 1)`). A multi-arity callback " <>
                 "crashes with `FunctionClauseError` on EVERY input. The fix " <>
                 "rewrites to `Regex.replace/3`, which natively supports " <>
                 "multi-arity callbacks."
             )
  end
end
