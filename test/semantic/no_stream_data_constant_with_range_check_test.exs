defmodule Credence.Semantic.NoStreamDataConstantWithRangeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoStreamDataConstantWithRange

  @real_message "incompatible types given to StreamData.integer/1:\n\n    StreamData.integer({min_length, max_length})\n\ngiven types:\n\n    -dynamic({term(), term()})-\n\nbut expected one of:\n\n    #1\n    dynamic(%Range{step: integer()})\n\n    #2\n    dynamic(%Range{})\n\nwhere \"max_length\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:59:28\n    max_length\n\nwhere \"min_length\" was given the type:\n\n    # type: dynamic() or integer()\n    # from: credence_check.ex:61:16\n    min_length = max(0, min_length)\n"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {63, 16}}
    assert NoStreamDataConstantWithRange.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoStreamDataConstantWithRange.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :warning,
      message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
      position: 0
    }

    refute NoStreamDataConstantWithRange.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {63, 16}}

    assert NoStreamDataConstantWithRange.to_issue(diag).rule ==
             :no_stream_data_constant_with_range
  end

  test "preserves the line in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {42, 10}}
    assert NoStreamDataConstantWithRange.to_issue(diag).meta.line == 42
  end
end
