defmodule Credence.Semantic.FixHallucinatedNaiveDatetimeAccessorCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedNaiveDatetimeAccessor

  @real_message "NaiveDateTime.minute/1 is undefined or private"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 5}}
    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "matches hour accessor diagnostic" do
    diag = %{severity: :warning, message: "NaiveDateTime.hour/1 is undefined or private", position: {4, 5}}
    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "matches day accessor diagnostic" do
    diag = %{severity: :warning, message: "NaiveDateTime.day/1 is undefined or private", position: {5, 5}}
    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "matches month accessor diagnostic" do
    diag = %{severity: :warning, message: "NaiveDateTime.month/1 is undefined or private", position: {6, 5}}
    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "matches day_of_week accessor diagnostic" do
    diag = %{severity: :warning, message: "NaiveDateTime.day_of_week/1 is undefined or private", position: {7, 5}}
    assert FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "ignores other NaiveDateTime diagnostics" do
    diag = %{severity: :warning, message: "NaiveDateTime.new/2 is undefined or private", position: {1, 1}}
    refute FixHallucinatedNaiveDatetimeAccessor.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 5}}

    assert FixHallucinatedNaiveDatetimeAccessor.to_issue(diag).rule ==
             :fix_hallucinated_naive_datetime_accessor
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert FixHallucinatedNaiveDatetimeAccessor.to_issue(diag).meta.line == 42
  end
end
