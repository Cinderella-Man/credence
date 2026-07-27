defmodule Credence.Semantic.NoHallucinatedStreamDataStringCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedStreamDataString

  @alpha_message "function StreamData.alpha_string/0 is undefined or private"
  @range_message "function StreamData.string_of_length/2 is undefined or private"

  test "matches the alpha_string diagnostic" do
    diag = %{severity: :warning, message: @alpha_message, position: {3, 5}}
    assert NoHallucinatedStreamDataString.match?(diag)
  end

  test "matches the string_of_length diagnostic" do
    diag = %{severity: :warning, message: @range_message, position: {7, 5}}
    assert NoHallucinatedStreamDataString.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated error", position: {1, 1}}
    refute NoHallucinatedStreamDataString.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message:
        "credence_check.ex: cannot compile module HallucinatedStreamDataString (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedStreamDataString.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @alpha_message, position: {3, 5}}
    assert NoHallucinatedStreamDataString.to_issue(diag).rule == :no_hallucinated_stream_data_string
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @alpha_message, position: {42, 10}}
    assert NoHallucinatedStreamDataString.to_issue(diag).meta.line == 42
  end
end
