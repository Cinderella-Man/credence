defmodule Credence.Semantic.NoNaiveDatetimeNewWithTupleCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoNaiveDatetimeNewWithTuple

  @real_message "incompatible types given to NaiveDateTime.new!/2:\n\n    NaiveDateTime.new!(Date.new!(year, month, day), {hour, minute, 0, 0})\n\ngiven types:\n\n    dynamic(%Date{}), -dynamic({term(), term(), integer(), integer()})-\n\nbut expected one of:\n\n    dynamic(%Date{}), dynamic(%Time{})\n\nwhere \"day\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:229:7\n    {:nth_day_of_month, day, {hour, minute}}"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {3, 19}}
    assert NoNaiveDatetimeNewWithTuple.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoNaiveDatetimeNewWithTuple.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :warning,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute NoNaiveDatetimeNewWithTuple.match?(diag)
  end

  test "ignores incompatible new!/2 diagnostics the fixer cannot repair" do
    for bad_argument <- ["binary()", "map()", "{integer(), integer()}"] do
      diag = %{
        severity: :warning,
        message:
          "incompatible types given to NaiveDateTime.new!/2\n\ngiven types:\n\n    dynamic(%Date{}), dynamic(#{bad_argument})",
        position: {1, 1}
      }

      refute NoNaiveDatetimeNewWithTuple.match?(diag)
    end
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {3, 19}}
    assert NoNaiveDatetimeNewWithTuple.to_issue(diag).rule == :no_naive_datetime_new_with_tuple
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoNaiveDatetimeNewWithTuple.to_issue(diag).meta.line == 42
  end
end
