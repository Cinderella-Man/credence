defmodule Credence.Pattern.FixEtsOptionsBareKeyposEquivalenceTest do
  @moduledoc """
  Same shape of argument as its sibling `FixEtsNewStringName`: the before-code
  raises on every input, so `assert_equivalent/2` has no pair of values to
  compare and the rewrite is a repair rather than a behaviour change.

  Both halves are executed rather than asserted.
  """
  use Credence.RuleCase, async: false

  alias Credence.Pattern.FixEtsOptionsBareKeypos

  test "marked as a repair: a flattened :keypos raises for every table" do
    mark_equivalence_repair(
      "always-fails. `:ets.new/2` reads its option list as a mix of bare atoms " <>
        "and two-element tuples, so a flattened `:keypos, n` raises ArgumentError " <>
        "for every table name, every key position and every caller — there is no " <>
        "input on which the before-code returns a table. Executed below: the " <>
        "flattened form raises, the tupled form returns a reference."
    )

    assert_raise ArgumentError, fn -> :ets.new(:kp_equiv_before, [:set, :keypos, 2]) end
  end

  test "the tupled form works" do
    table = :ets.new(:kp_equiv_after, [:set, {:keypos, 2}])

    assert is_reference(table)
    :ets.delete(table)
  end

  test "the rewritten module creates a table where the original raised" do
    before_src = """
    defmodule KpEquivRule do
      def start, do: :ets.new(:kp_equiv_rule, [:set, :keypos, 2])
    end
    """

    fixed = fix(FixEtsOptionsBareKeypos, before_src)
    assert fixed != before_src

    assert_raise ArgumentError, fn -> call_fixed(before_src, KpEquivRule, :start, []) end

    table = call_fixed(fixed, KpEquivRule, :start, [])
    assert is_reference(table)

    # And the option actually took effect: with keypos 2, the key is element 2.
    :ets.insert(table, {:ignored, :real_key, :value})
    assert [{:ignored, :real_key, :value}] = :ets.lookup(table, :real_key)
    :ets.delete(table)
  end
end
