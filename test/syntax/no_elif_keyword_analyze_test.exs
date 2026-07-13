defmodule Credence.Syntax.NoElifKeywordAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoElifKeyword

  defp analyze(code), do: NoElifKeyword.analyze(code)

  test "flags code containing elif" do
    input = """
    if sequence <= last_seq do
      {:reply, {:ok, :duplicate}, state}
    elif sequence > last_seq + 1 do
      {:reply, {:ok, :buffered}, state}
    else
      {:reply, {:ok, :received}, state}
    end
    """

    assert [%Issue{rule: :no_elif_keyword} | _] = analyze(input)
  end

  test "reports one issue per elif" do
    input = """
    if a do
      1
    elif b do
      2
    elif c do
      3
    else
      4
    end
    """

    assert [%Issue{rule: :no_elif_keyword}, %Issue{rule: :no_elif_keyword}] = analyze(input)
  end

  test "leaves valid Elixir code alone" do
    input = """
    cond do
      x == nil -> {:error, :missing}
      y <= 0 -> {:error, :invalid}
      true -> {:ok, y}
    end
    """

    assert analyze(input) == []
  end

  test "leaves plain if/else alone" do
    input = """
    if x do
      a
    else
      b
    end
    """

    assert analyze(input) == []
  end
end
