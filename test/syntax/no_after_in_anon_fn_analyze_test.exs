defmodule Credence.Syntax.NoAfterInAnonFnAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoAfterInAnonFn

  defp analyze(code), do: NoAfterInAnonFn.analyze(code)

  test "flags the unparseable code" do
    code = """
    spawn_monitor(fn ->
      result = processor.(task)
      send(parent, {:done, result})
    after
      0 -> nil
    end)
    """

    assert [%Issue{rule: :no_after_in_anon_fn}] = analyze(code)
  end

  test "leaves good code alone" do
    # fn without after
    assert analyze("fn x -> x end") == []

    # try with after (valid)
    assert analyze("""
    try do
      x
    after
      y
    end
    """) == []

    # receive with after (valid)
    assert analyze("""
    receive do
      :ok -> :ok
    after
      5000 -> :timeout
    end
    """) == []
  end
end
