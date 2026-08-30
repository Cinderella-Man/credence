defmodule Credence.Semantic.FixHallucinatedCalendarIsoAccessorCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedCalendarIsoAccessor

  @date_message "Calendar.ISO.date/1 is undefined or private"
  @time_message "Calendar.ISO.time/1 is undefined or private"

  test "matches the diagnostic for Calendar.ISO.date/1" do
    diag = %{severity: :warning, message: @date_message, position: {3, 25}}
    assert FixHallucinatedCalendarIsoAccessor.match?(diag)
  end

  test "matches the diagnostic for Calendar.ISO.time/1" do
    diag = %{severity: :warning, message: @time_message, position: {4, 25}}
    assert FixHallucinatedCalendarIsoAccessor.match?(diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    diag = %{severity: :warning, message: @date_message, position: {3, 25}}

    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(diag))

    assert winner == FixHallucinatedCalendarIsoAccessor
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedCalendarIsoAccessor.match?(diag)
  end

  test "ignores other Calendar.ISO functions" do
    diag = %{
      severity: :warning,
      message: "Calendar.ISO.valid_date?/1 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedCalendarIsoAccessor.match?(diag)
  end

  test "ignores other arities (no single obvious intent for date/3)" do
    diag = %{
      severity: :warning,
      message: "Calendar.ISO.date/3 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedCalendarIsoAccessor.match?(diag)
  end

  test "ignores a user module whose path merely ends in Calendar.ISO" do
    diag = %{
      severity: :warning,
      message: "MyApp.Calendar.ISO.date/1 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedCalendarIsoAccessor.match?(diag)
  end

  test "ignores error-severity diagnostics" do
    diag = %{severity: :error, message: @date_message, position: {3, 25}}
    refute FixHallucinatedCalendarIsoAccessor.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @date_message, position: {3, 25}}

    assert FixHallucinatedCalendarIsoAccessor.to_issue(diag).rule ==
             :fix_hallucinated_calendar_iso_accessor
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @date_message, position: {42, 10}}
    assert FixHallucinatedCalendarIsoAccessor.to_issue(diag).meta.line == 42
  end
end
