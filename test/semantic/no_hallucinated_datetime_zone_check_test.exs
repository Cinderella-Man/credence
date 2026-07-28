defmodule Credence.Semantic.NoHallucinatedDatetimeZoneCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoHallucinatedDatetimeZone

  @real_message "unknown key .zone in expression:\n\n    dt.zone\n\nthe given type does not have the given key:\n\n    dynamic(%DateTime{\n      year: term(),\n      month: term(),\n      day: term(),\n      hour: term(),\n      minute: term(),\n      second: term(),\n      time_zone: term(),\n      zone_abbr: term(),\n      utc_offset: term(),\n      std_offset: term(),\n      microsecond: term(),\n      calendar: term()\n    })\n\nwhere \"dt\" was given the type:\n\n    # type: dynamic(%DateTime{})\n    # from: credence_check.ex:139:33\n    %DateTime{} = dt\n"

  test "matches the diagnostic" do
    diag = %{
      severity: :warning,
      message: @real_message,
      position: {139, 47},
      file: "credence_check.ex"
    }

    assert NoHallucinatedDatetimeZone.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoHallucinatedDatetimeZone.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :warning,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute NoHallucinatedDatetimeZone.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :warning,
      message: @real_message,
      position: {139, 47},
      file: "credence_check.ex"
    }

    assert NoHallucinatedDatetimeZone.to_issue(diag).rule == :no_hallucinated_datetime_zone
  end

  test "sets the line in issue meta" do
    diag = %{
      severity: :warning,
      message: @real_message,
      position: {42, 10},
      file: "credence_check.ex"
    }

    assert NoHallucinatedDatetimeZone.to_issue(diag).meta.line == 42
  end
end
