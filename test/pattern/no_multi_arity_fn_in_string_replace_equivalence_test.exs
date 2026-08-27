defmodule Credence.Pattern.NoMultiArityFnInStringReplaceEquivalenceTest do
  @moduledoc """
  Repair rule. `String.replace/3` only accepts arity-1 function replacements
  (guard: `is_function(replacement, 1)`), so passing a multi-arity callback
  always crashes at runtime with `FunctionClauseError` on EVERY input. There
  is no valid runtime behaviour to preserve — the fix rewrites to
  `Regex.replace/3`, which natively supports multi-arity callbacks.
  """
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMultiArityFnInStringReplace
  alias Credence.RuleHelpers

  test "does not rewrite a literal string pattern to invalid Regex.replace" do
    source = ~S'String.replace("abc", "a", fn _, group -> group end)'

    emitted = fix(NoMultiArityFnInStringReplace, source)

    confirm_fix(emitted, source)
  end

  test "the emitted regex-pattern repair executes" do
    source = """
    unless String.replace("abc", ~r/(a)/, fn _, group -> group end) == "abc" do
          raise "the broken call unexpectedly returned"
        end
    """

    emitted = fix(NoMultiArityFnInStringReplace, source)

    expected = """
    unless Regex.replace(~r/(a)/, "abc", fn _, group -> group end) == "abc" do
          raise "the broken call unexpectedly returned"
        end
    """

    confirm_fix(emitted, expected)
    assert {:ok, []} = RuleHelpers.compile_and_capture(emitted)
  end

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
