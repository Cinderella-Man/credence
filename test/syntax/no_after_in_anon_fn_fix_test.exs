defmodule Credence.Syntax.NoAfterInAnonFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoAfterInAnonFn

  defp analyze(code), do: NoAfterInAnonFn.analyze(code)
  defp fix(code), do: NoAfterInAnonFn.fix(code)

  test "fixes the syntax error" do
    input = """
    spawn_monitor(fn ->
      result = processor.(task)
      send(parent, {:done, result})
    after
      0 -> nil
    end)
    """

    expected = """
    spawn_monitor(fn ->
      result = processor.(task)
      send(parent, {:done, result})
    end)
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    spawn_monitor(fn ->
      result = processor.(task)
      send(parent, {:done, result})
    after
      0 -> nil
    end)
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    spawn_monitor(fn ->
      result = processor.(task)
      send(parent, {:done, result})
    after
      0 -> nil
    end)
    """

    assert valid_syntax?(fix(input))
  end
end
