defmodule Credence.Semantic.NoPipeIntoUnaryArithmeticCheckTest do
  use ExUnit.Case, async: true

  alias Credence.Semantic.NoPipeIntoUnaryArithmetic

  @message "piping into a unary operator is not supported, please use the qualified name: " <>
             "Kernel.+(1), instead of +1"

  test "matches the diagnostic" do
    assert NoPipeIntoUnaryArithmetic.match?(%{severity: :error, message: @message, position: 0})
  end

  test "ignores unrelated diagnostics" do
    refute NoPipeIntoUnaryArithmetic.match?(%{
             severity: :error,
             message: "undefined function foo/1",
             position: {1, 1}
           })
  end

  test "attributes the issue to this rule" do
    assert NoPipeIntoUnaryArithmetic.to_issue(%{
             severity: :error,
             message: @message,
             position: 0
           }).rule == :no_pipe_into_unary_arithmetic
  end

  describe "through the real compiler" do
    @source """
    defmodule PipeUnaryWitness do
      def bump(x), do: x |> + 1
    end
    """

    # Not a fabricated map. This asserts the compiler still refuses this code,
    # still words the refusal this way, and that this rule wins its slot.
    test "the compiler emits a diagnostic this rule matches" do
      {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(@source)

      assert Enum.any?(diagnostics, &NoPipeIntoUnaryArithmetic.match?/1),
             "got: #{inspect(Enum.map(diagnostics, & &1.message))}"
    end

    # The fact the rule is built around: this exception carries NO line. The
    # compiler raises rather than emitting a diagnostic, so the synthesized one
    # is `position: 0`. A version of this rule that scoped its fix to the
    # diagnostic's line found nothing and reported `:no_op` forever.
    test "and that diagnostic has no usable line" do
      {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(@source)
      diagnostic = Enum.find(diagnostics, &NoPipeIntoUnaryArithmetic.match?/1)

      assert diagnostic.position in [0, nil],
             "this rule ignores the diagnostic line because there isn't one; if that " <>
               "changed, the fix can and should be scoped again"
    end

    test "the issue is attributed to this rule end-to-end" do
      assert Enum.any?(
               Credence.Semantic.analyze(@source, source: @source),
               &(&1.rule == :no_pipe_into_unary_arithmetic)
             )
    end
  end
end
