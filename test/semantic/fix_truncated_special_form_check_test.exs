defmodule Credence.Semantic.FixTruncatedSpecialFormCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixTruncatedSpecialForm

  @module_diag %{
    severity: :error,
    message: "undefined variable \"__MODULE\"",
    position: {6, 26}
  }

  test "matches the diagnostic for __MODULE" do
    assert FixTruncatedSpecialForm.match?(@module_diag)
  end

  test "matches the diagnostic for __ENV" do
    diag = %{severity: :error, message: "undefined variable \"__ENV\"", position: {1, 1}}
    assert FixTruncatedSpecialForm.match?(diag)
  end

  test "matches the diagnostic for __DIR" do
    diag = %{severity: :error, message: "undefined variable \"__DIR\"", position: {1, 1}}
    assert FixTruncatedSpecialForm.match?(diag)
  end

  test "matches the diagnostic for __CALLER" do
    diag = %{severity: :error, message: "undefined variable \"__CALLER\"", position: {1, 1}}
    assert FixTruncatedSpecialForm.match?(diag)
  end

  test "matches the diagnostic for __STACKTRACE" do
    diag = %{severity: :error, message: "undefined variable \"__STACKTRACE\"", position: {1, 1}}
    assert FixTruncatedSpecialForm.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "undefined variable \"foo\"", position: {1, 1}}
    refute FixTruncatedSpecialForm.match?(diag)
  end

  test "ignores undefined function diagnostics" do
    diag = %{severity: :error, message: "undefined function foo/1", position: {1, 1}}
    refute FixTruncatedSpecialForm.match?(diag)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: "undefined variable \"__MODULE\"", position: {1, 1}}
    refute FixTruncatedSpecialForm.match?(diag)
  end

  test "ignores __MODULE_ (single trailing underscore is a different name)" do
    diag = %{severity: :error, message: "undefined variable \"__MODULE_\"", position: {1, 1}}
    refute FixTruncatedSpecialForm.match?(diag)
  end

  test "ignores names that merely start with a known dunder, like __MODULEX" do
    diag = %{severity: :error, message: "undefined variable \"__MODULEX\"", position: {1, 1}}
    refute FixTruncatedSpecialForm.match?(diag)
  end

  test "ignores names that merely end with a known dunder, like foo__MODULE" do
    diag = %{severity: :error, message: "undefined variable \"foo__MODULE\"", position: {1, 1}}
    refute FixTruncatedSpecialForm.match?(diag)
  end

  test "ignores messages with trailing context (anchored match)" do
    diag = %{
      severity: :error,
      message: "undefined variable \"__MODULE\" (context Elixir)",
      position: {1, 1}
    }

    refute FixTruncatedSpecialForm.match?(diag)
  end

  test "should_report? is true when the fix would rewrite the source" do
    source = """
    defmodule EnvTest do
      defmacro get_env, do: __ENV
    end
    """

    diag = %{severity: :error, message: "undefined variable \"__ENV\"", position: {2, 25}}
    assert FixTruncatedSpecialForm.should_report?(diag, source)
  end

  test "should_report? is false when the position does not show the truncated form" do
    source = """
    defmodule EnvTest do
      defmacro get_env, do: __ENV
    end
    """

    diag = %{severity: :error, message: "undefined variable \"__ENV\"", position: {2, 1}}
    refute FixTruncatedSpecialForm.should_report?(diag, source)
  end

  test "attributes the issue to this rule" do
    assert FixTruncatedSpecialForm.to_issue(@module_diag).rule == :fix_truncated_special_form
  end

  test "issue message carries the diagnostic text" do
    assert FixTruncatedSpecialForm.to_issue(@module_diag).message ==
             "undefined variable \"__MODULE\""
  end

  test "issue meta carries the line" do
    assert FixTruncatedSpecialForm.to_issue(@module_diag).meta == %{line: 6}
  end
end
