defmodule Credence.Semantic.FixFnArityInKeywordValueCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixFnArityInKeywordValue

  # Captured verbatim from `Code.with_diagnostics` compiling @flagship_source
  # on Elixir 1.20 (the `:push / 4` expression sits on line 4).
  @real_diag %{
    severity: :warning,
    message:
      "incompatible types given to Kernel.//2:\n\n    :push / 4\n\ngiven types:\n\n    -:push-, integer()\n\nbut expected one of:\n\n    float() or integer(), float() or integer()\n",
    position: {4, 49}
  }

  @flagship_source """
  defmodule FixFnArityExample do
    def push(server, name, value, window_size) do
      unless is_number(value) do
        raise FunctionClauseError, function: :push/4
      end
      :ok
    end
  end
  """

  test "matches the diagnostic" do
    assert FixFnArityInKeywordValue.match?(@real_diag)
  end

  test "matches the diagnostic at error severity too" do
    assert FixFnArityInKeywordValue.match?(%{@real_diag | severity: :error})
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixFnArityInKeywordValue.match?(diag)
  end

  test "attributes the issue to this rule" do
    issue = FixFnArityInKeywordValue.to_issue(@real_diag)
    assert issue.rule == :fix_fn_arity_in_keyword_value
    assert issue.meta.line == 4
  end

  test "phase dispatch routes the diagnostic to this rule" do
    winner =
      Credence.RuleHelpers.discover_rules(Credence.Semantic.Rule)
      |> Enum.find(fn rule -> rule.match?(@real_diag) end)

    assert winner == FixFnArityInKeywordValue
  end

  test "should_report?: true when the fix would rewrite the source" do
    assert FixFnArityInKeywordValue.should_report?(@real_diag, @flagship_source)
  end

  test "should_report?: false for a Kernel.//2 warning with no fixable raise" do
    source = """
    defmodule PlainArithmetic do
      def broken, do: :push / 4
    end
    """

    diag = %{@real_diag | position: {2, 19}}
    refute FixFnArityInKeywordValue.should_report?(diag, source)
  end

  test "should_report?: false when the exception struct lacks function/arity fields" do
    source = """
    defmodule OtherException do
      def broken do
        raise ArgumentError, function: :push/4
      end
    end
    """

    diag = %{@real_diag | position: {3, 36}}
    refute FixFnArityInKeywordValue.should_report?(diag, source)
  end
end
