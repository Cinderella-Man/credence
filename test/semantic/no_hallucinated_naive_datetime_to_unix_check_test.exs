defmodule Credence.Semantic.NoHallucinatedNaiveDatetimeToUnixCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedNaiveDatetimeToUnix

  @real_message "NaiveDateTime.to_unix/2 is undefined or private. Did you mean one of:\n\n      * to_unix/1\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {5, 28}}
    assert NoHallucinatedNaiveDatetimeToUnix.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedNaiveDatetimeToUnix.match?(diag)
  end

  test "ignores other NaiveDateTime diagnostics" do
    diag = %{severity: :warning, message: "NaiveDateTime.to_unix/1 is undefined or private", position: {1, 1}}
    refute NoHallucinatedNaiveDatetimeToUnix.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {5, 28}}

    assert NoHallucinatedNaiveDatetimeToUnix.to_issue(diag).rule ==
             :no_hallucinated_naive_datetime_to_unix
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoHallucinatedNaiveDatetimeToUnix.to_issue(diag).meta.line == 42
  end
end
