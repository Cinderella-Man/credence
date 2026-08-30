defmodule Credence.Pattern.FixEtsNewStringNameEquivalenceTest do
  @moduledoc """
  The standard `assert_equivalent/2` harness does not apply here, and the reason
  is the rule's entire warrant.

  That harness evaluates a before-expression and an after-expression over a set
  of inputs and demands they agree. `:ets.new("cache", [:set])` **raises
  ArgumentError on every input**, so there is no value for them to agree on —
  and the project's equivalence policy is explicit that a rule whose "before"
  returns a valid value on some input is a behaviour change rather than a
  repair. This one returns a valid value on no input at all, which is what makes
  the rewrite a repair.

  So what is asserted instead is the pair of facts that claim rests on, both by
  EXECUTION: the before really does raise, and the after really does work.
  """
  use Credence.RuleCase, async: false

  alias Credence.Pattern.FixEtsNewStringName

  test "marked as a repair: the before-code raises on every input" do
    mark_equivalence_repair(
      "always-fails. `:ets.new/2` requires an atom name and raises ArgumentError " <>
        "on a string for EVERY option list and every caller — there is no input " <>
        "on which the before-code returns a value, so there is no behaviour to " <>
        "preserve. Both halves of that claim are executed below rather than " <>
        "asserted: the string form raises, the atom form returns a table."
    )

    assert_raise ArgumentError, fn -> :ets.new("ets_equiv_before", [:set]) end
  end

  test "the after-code works" do
    table = :ets.new(:ets_equiv_after, [:set])

    assert is_reference(table)
    :ets.delete(table)
  end

  test "the rewritten module creates a table where the original raised" do
    before_src = """
    defmodule EtsEquivRule do
      def start, do: :ets.new("ets_equiv_rule", [:set])
    end
    """

    fixed = fix(FixEtsNewStringName, before_src)
    assert fixed != before_src

    assert_raise ArgumentError, fn -> call_fixed(before_src, EtsEquivRule, :start, []) end

    table = call_fixed(fixed, EtsEquivRule, :start, [])
    assert is_reference(table)
    :ets.delete(table)
  end
end
