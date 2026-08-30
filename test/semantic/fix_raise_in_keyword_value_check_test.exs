defmodule Credence.Semantic.FixRaiseInKeywordValueCheckTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixRaiseInKeywordValue

  @diagnostic_msg "missing parentheses for expression following \"do:\" keyword. Parentheses are required to solve ambiguity inside keywords.\n\nThis error happens when you have function calls without parentheses inside keywords. For example:\n\n    function(arg, one: nested_call a, b, c)\n    function(arg, one: if expr, do: :this, else: :that)\n\nIn the examples above, we don't know if the arguments \"b\" and \"c\" apply to the function \"function\" or \"nested_call\". Or if the keywords \"do\" and \"else\" apply to the function \"function\" or \"if\". You can solve this by explicitly adding parentheses:\n\n    function(arg, one: if(expr, do: :this, else: :that))\n    function(arg, one: nested_call(a, b, c))\n\nAmbiguity found at:"

  @buggy_source """
  defmodule CredenceRaiseInKeywordLiveRepro do
    def f(_, _), do: raise ArgumentError, "bad argument"
  end
  """

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: {13, 1}}
    assert FixRaiseInKeywordValue.match?(diag)
  end

  test "matches the live compiler diagnostic on this Elixir" do
    {:ok, diags} = RuleHelpers.compile_and_capture(@buggy_source)
    assert Enum.any?(diags, &FixRaiseInKeywordValue.match?/1)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixRaiseInKeywordValue.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @diagnostic_msg, position: {13, 1}}
    refute FixRaiseInKeywordValue.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: {13, 1}}
    assert FixRaiseInKeywordValue.to_issue(diag).rule == :fix_raise_in_keyword_value
  end

  test "sets the line in issue meta from a tuple position" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: {42, 7}}
    assert FixRaiseInKeywordValue.to_issue(diag).meta.line == 42
  end

  test "sets the line in issue meta from a bare integer position" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: 42}
    assert FixRaiseInKeywordValue.to_issue(diag).meta.line == 42
  end

  test "should_report? is true when the source has a bare raise in a do: value" do
    diag = %{severity: :warning, message: @diagnostic_msg, position: 2}
    assert FixRaiseInKeywordValue.should_report?(diag, @buggy_source)
  end

  test "should_report? is false when the ambiguity is not a raise call" do
    source = """
    defmodule M do
      def f(x), do: foo x, bar: 1
    end
    """

    diag = %{severity: :warning, message: @diagnostic_msg, position: 2}
    refute FixRaiseInKeywordValue.should_report?(diag, source)
  end

  test "should_report? does not claim an unrelated diagnostic when a bare raise exists elsewhere" do
    source = """
    defmodule CredenceRaiseInKeywordPositionMismatch do
      def unrelated(x), do: foo x, bar: 1
      def raises(_, _), do: raise ArgumentError, "bad"
    end
    """

    {_, diags} = RuleHelpers.compile_and_capture(source)

    diag =
      Enum.find(diags, fn diag ->
        diag.position == 2 and FixRaiseInKeywordValue.match?(diag)
      end)

    refute FixRaiseInKeywordValue.should_report?(diag, source)
    confirm_fix(FixRaiseInKeywordValue.fix(source, diag), source)
  end

  test "should_report? is false when the raise is already parenthesised" do
    source = """
    defmodule M do
      def f(_, _), do: raise(ArgumentError, "bad argument")
    end
    """

    diag = %{severity: :warning, message: @diagnostic_msg, position: 2}
    refute FixRaiseInKeywordValue.should_report?(diag, source)
  end
end
