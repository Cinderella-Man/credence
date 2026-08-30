defmodule Credence.Semantic.NoHallucinatedDatetimeInfoCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedDatetimeInfo

  @real_message "DateTime.info?/1 is undefined or private"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {81, 40}}
    assert NoHallucinatedDatetimeInfo.match?(diag)
  end

  test "matches with extended message" do
    diag = %{
      severity: :warning,
      message: "DateTime.info?/1 is undefined or private. Did you mean:\n\n    * date/1\n",
      position: {81, 40}
    }

    assert NoHallucinatedDatetimeInfo.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedDatetimeInfo.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message:
        "credence_check.ex: cannot compile module HallucinatedDateTimeInfo (errors have been logged)",
      position: 0
    }

    refute NoHallucinatedDatetimeInfo.match?(diag)
  end

  test "ignores other undefined DateTime functions" do
    diag = %{
      severity: :warning,
      message: "DateTime.parse/2 is undefined or private",
      position: {1, 1}
    }

    refute NoHallucinatedDatetimeInfo.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {81, 40}}
    assert NoHallucinatedDatetimeInfo.to_issue(diag).rule == :no_hallucinated_datetime_info
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoHallucinatedDatetimeInfo.to_issue(diag).meta.line == 42
  end

  test "preserves the original diagnostic message" do
    diag = %{severity: :warning, message: @real_message, position: {81, 40}}
    assert NoHallucinatedDatetimeInfo.to_issue(diag).message == @real_message
  end
end
