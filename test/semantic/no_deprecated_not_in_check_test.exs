defmodule Credence.Semantic.NoDeprecatedNotInCheckTest do
  @moduledoc """
  The compiler emits this rule's diagnostic itself, so the tests that matter
  most are the ones that go through it rather than through a hand-written map.

  185 of 185 semantic test files fabricate their diagnostic (docs/22 T1), and a
  fabricated one proves only that `match?/1` agrees with the string the test
  author typed. The `through the real compiler` case below is the one that
  proves the warning exists, is still worded that way, and reaches this rule.
  """
  use ExUnit.Case, async: true

  alias Credence.Semantic.NoDeprecatedNotIn

  @message ~s("not expr1 in expr2" is deprecated, use "expr1 not in expr2" instead)

  test "matches the deprecation diagnostic" do
    assert NoDeprecatedNotIn.match?(%{severity: :warning, message: @message, position: {2, 21}})
  end

  test "ignores unrelated diagnostics" do
    refute NoDeprecatedNotIn.match?(%{
             severity: :warning,
             message: "variable \"x\" is unused",
             position: {1, 1}
           })
  end

  # The near miss: another deprecation, on the same operator family.
  test "ignores a different deprecation" do
    refute NoDeprecatedNotIn.match?(%{
             severity: :warning,
             message: ~s(use of "^^^" is deprecated),
             position: {1, 1}
           })
  end

  test "attributes the issue to this rule" do
    issue =
      NoDeprecatedNotIn.to_issue(%{severity: :warning, message: @message, position: {2, 21}})

    assert issue.rule == :no_deprecated_not_in
    assert issue.meta.line == 2
  end

  describe "through the real compiler" do
    @source """
    defmodule NotInCheckWitness do
      def missing?(x, list), do: not x in list
    end
    """

    # Not a fabricated map: this asserts the compiler still emits the warning,
    # still words it this way, and that this rule wins the dispatch slot for it.
    # If Elixir ever rewords or removes the deprecation, this is what tells us —
    # rather than the rule silently going dead in production.
    test "the compiler emits a diagnostic this rule matches" do
      {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(@source)

      assert Enum.any?(diagnostics, &NoDeprecatedNotIn.match?/1),
             "no compiler diagnostic matched; got: #{inspect(Enum.map(diagnostics, & &1.message))}"
    end

    test "the issue is attributed to this rule end-to-end" do
      assert Enum.any?(
               Credence.Semantic.analyze(@source, source: @source),
               &(&1.rule == :no_deprecated_not_in)
             )
    end
  end
end
