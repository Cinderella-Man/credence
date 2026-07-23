defmodule Credence.Semantic.FixHallucinatedNaiveDatetimeAccessorCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedNaiveDatetimeAccessor

  @minute_message "NaiveDateTime.minute/1 is undefined or private"

  test "matches the diagnostic for NaiveDateTime.minute/1" do
    diag = %{severity: :warning, message: @minute_message, position: {3, 28}}
    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "matches the diagnostic for NaiveDateTime.hour/1" do
    diag = %{
      severity: :warning,
      message: "NaiveDateTime.hour/1 is undefined or private",
      position: {4, 26}
    }

    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "matches the diagnostic for NaiveDateTime.day/1" do
    diag = %{
      severity: :warning,
      message: "NaiveDateTime.day/1 is undefined or private",
      position: {5, 25}
    }

    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "matches the diagnostic for NaiveDateTime.month/1" do
    diag = %{
      severity: :warning,
      message: "NaiveDateTime.month/1 is undefined or private",
      position: {6, 27}
    }

    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    diag = %{severity: :warning, message: @minute_message, position: {3, 28}}

    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(diag))

    assert winner == FixHallucinatedNaiveDatetimeAccessor
  end

  test "ignores day_of_week (not a %NaiveDateTime{} field — no safe field-access rewrite)" do
    diag = %{
      severity: :warning,
      message: "NaiveDateTime.day_of_week/1 is undefined or private",
      position: {7, 34}
    }

    refute FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "ignores other NaiveDateTime diagnostics" do
    diag = %{
      severity: :warning,
      message: "NaiveDateTime.new/2 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "ignores other arities (no single obvious intent for minute/2)" do
    diag = %{
      severity: :warning,
      message: "NaiveDateTime.minute/2 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "ignores a user module whose path merely ends in NaiveDateTime" do
    diag = %{
      severity: :warning,
      message: "MyApp.NaiveDateTime.minute/1 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "ignores error-severity diagnostics" do
    diag = %{severity: :error, message: @minute_message, position: {3, 28}}
    refute FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @minute_message, position: {3, 28}}

    assert FixHallucinatedNaiveDatetimeAccessor.to_issue(diag).rule ==
             :fix_hallucinated_naive_datetime_accessor
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @minute_message, position: {42, 10}}
    assert FixHallucinatedNaiveDatetimeAccessor.to_issue(diag).meta.line == 42
  end
end
