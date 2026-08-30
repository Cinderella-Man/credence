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

  test "does not report invalid after clauses outside anonymous functions" do
    invalid_if = """
    if condition do
      work()
    after
      cleanup()
    end
    """

    invalid_case = """
    case value do
      _ -> work()
    after
      cleanup()
    end
    """

    invalid_def = """
    def work do
      step()
    after
      cleanup()
    end
    """

    bare_after = """
    work()
    after
      cleanup()
    """

    assert analyze(invalid_if) == []
    assert analyze(invalid_case) == []
    assert analyze(invalid_def) == []
    assert analyze(bare_after) == []
  end
end
