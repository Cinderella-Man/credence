defmodule Credence.Semantic.FixMultipleDefaultArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixMultipleDefaultArgs

  @real_message "def greet/2 defines defaults multiple times. Elixir allows defaults to be declared once per definition. Instead of:\n\n    def foo(:first_clause, b \\ :default) do ... end\n    def foo(:second_clause, b \\ :default) do ... end\n\none should write:\n\n    def foo(a, b \\ :default)\n    def foo(:first_clause, b) do ... end\n    def foo(:second_clause, b) do ... end\n\nthe previous clause is defined on line 2\n"

  @impl_message "module attribute @impl was not set for function monotonic/1 callback (specified in Clock). This either means you forgot to add the \"@impl true\" annotation before the definition or that you are accidentally overriding this callback"

  @fixable_source """
  defmodule CredenceFixMultipleDefaultArgsCheckFixture do
    def greet(:hello, name \\\\ "world") do
      "Hello, \#{name}!"
    end

    def greet(:goodbye, name \\\\ "world") do
      "Goodbye, \#{name}!"
    end
  end
  """

  test "the real compiler error matches this rule and analyze reports it" do
    {:error, diags} = Credence.RuleHelpers.compile_and_capture(@fixable_source)
    assert Enum.any?(diags, &FixMultipleDefaultArgs.match?/1)

    assert [%Credence.Issue{rule: :fix_multiple_default_args}] =
             Credence.Semantic.analyze(@fixable_source)
  end

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert FixMultipleDefaultArgs.match?(diag)
  end

  test "matches the defp variant of the message" do
    diag = %{
      severity: :error,
      message: "defp greet/2 defines defaults multiple times.",
      position: {6, 7}
    }

    assert FixMultipleDefaultArgs.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "undefined function foo/1", position: {1, 1}}
    refute FixMultipleDefaultArgs.match?(diag)
  end

  test "ignores warning severity for defines defaults multiple times" do
    diag = %{severity: :warning, message: @real_message, position: {6, 7}}
    refute FixMultipleDefaultArgs.match?(diag)
  end

  test "ignores missing @impl callback warnings (out of scope for this rule)" do
    diag = %{severity: :warning, message: @impl_message, position: {69, 1}}
    refute FixMultipleDefaultArgs.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert FixMultipleDefaultArgs.to_issue(diag).rule == :fix_multiple_default_args
  end

  test "issue message names the function, arity, and def kind" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}

    assert FixMultipleDefaultArgs.to_issue(diag).message ==
             "def greet/2 defines defaults multiple times"

    defp_diag = %{
      severity: :error,
      message: "defp greet/2 defines defaults multiple times.",
      position: {6, 7}
    }

    assert FixMultipleDefaultArgs.to_issue(defp_diag).message ==
             "defp greet/2 defines defaults multiple times"
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {6, 7}}
    assert FixMultipleDefaultArgs.to_issue(diag).meta.line == 6
  end

  test "does not report conflicting default values (no safe fix)" do
    source = """
    defmodule CredenceFixMultipleDefaultArgsConflictFixture do
      def greet(:a, name \\\\ "world"), do: name

      def greet(:b, name \\\\ "earth"), do: name
    end
    """

    assert Credence.Semantic.analyze(source) == []
  end

  test "does not report defaults on different positions per clause (no safe fix)" do
    source = """
    defmodule CredenceFixMultipleDefaultArgsMixedPosFixture do
      def greet(a \\\\ 1, b) do
        a + b
      end

      def greet(a, b \\\\ 2) do
        a - b
      end
    end
    """

    assert Credence.Semantic.analyze(source) == []
  end
end
