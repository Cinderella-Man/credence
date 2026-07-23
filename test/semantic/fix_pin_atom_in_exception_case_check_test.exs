defmodule Credence.Semantic.FixPinAtomInExceptionCaseCheckTest do
  use ExUnit.Case

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixPinAtomInExceptionCase

  # Real message captured from `Code.with_diagnostics` on Elixir 1.20 for a
  # bare `^exception ->` clause matched against a rescued exception.
  @real_message """
  the following clause will never match:

      ^exception ->

  because it attempts to match on the result of:

      e

  which has type:

      %{..., __exception__: term(), __struct__: atom()}

  where "exception" was given the type:

      # type: ArgumentError
      # from: nofile:3:15
      exception = ArgumentError
  """

  @buggy_source """
  defmodule CredencePinAtomLiveRepro do
    def run(fun) do
      exception = ArgumentError

      try do
        fun.()
      rescue
        e ->
          case e do
            ^exception -> :expected
            _ -> :other
          end
      end
    end
  end
  """

  test "matches the real never-match diagnostic for a bare pinned exception" do
    diag = %{severity: :warning, message: @real_message, position: {9, 11}}
    assert FixPinAtomInExceptionCase.match?(diag)
  end

  test "matches the live compiler diagnostic on this Elixir" do
    {:ok, diags} = RuleHelpers.compile_and_capture(@buggy_source)
    assert Enum.any?(diags, &FixPinAtomInExceptionCase.match?/1)
  end

  test "matches the older __exception__: true form of the type" do
    msg = String.replace(@real_message, "__exception__: term()", "__exception__: true")
    diag = %{severity: :warning, message: msg, position: {9, 11}}
    assert FixPinAtomInExceptionCase.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixPinAtomInExceptionCase.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {9, 11}}
    refute FixPinAtomInExceptionCase.match?(diag)
  end

  test "ignores a guarded pin clause (fix does not cover guards)" do
    msg =
      String.replace(
        @real_message,
        "^exception ->",
        "^exception when is_atom(exception) ->"
      )

    diag = %{severity: :warning, message: msg, position: {9, 11}}
    refute FixPinAtomInExceptionCase.match?(diag)
  end

  test "ignores never-match clauses that are not a bare pin" do
    msg = String.replace(@real_message, "^exception ->", ":foo ->")
    diag = %{severity: :warning, message: msg, position: 9}
    refute FixPinAtomInExceptionCase.match?(diag)
  end

  test "ignores clause-will-never-match without exception context" do
    msg = """
    the following clause will never match:

        ^expected ->

    because it attempts to match on the result of:

        x

    which has type:

        :error
    """

    diag = %{severity: :warning, message: msg, position: {5, 3}}
    refute FixPinAtomInExceptionCase.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {9, 11}}
    assert FixPinAtomInExceptionCase.to_issue(diag).rule == :fix_pin_atom_in_exception_case
  end

  test "sets the line in issue meta from a tuple position" do
    diag = %{severity: :warning, message: @real_message, position: {42, 11}}
    assert FixPinAtomInExceptionCase.to_issue(diag).meta.line == 42
  end

  test "sets the line in issue meta from a bare integer position" do
    diag = %{severity: :warning, message: @real_message, position: 42}
    assert FixPinAtomInExceptionCase.to_issue(diag).meta.line == 42
  end

  test "should_report? is true when the flagged line carries the bare pin" do
    diag = %{severity: :warning, message: @real_message, position: {10, 11}}
    assert FixPinAtomInExceptionCase.should_report?(diag, @buggy_source)
  end

  test "should_report? is false when the flagged line has no bare pin" do
    diag = %{severity: :warning, message: @real_message, position: {11, 11}}
    refute FixPinAtomInExceptionCase.should_report?(diag, @buggy_source)
  end
end
