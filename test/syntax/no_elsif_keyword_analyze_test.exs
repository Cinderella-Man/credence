defmodule Credence.Syntax.NoElsifKeywordAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoElsifKeyword

  defp analyze(code), do: NoElsifKeyword.analyze(code)

  test "flags code containing elsif" do
    input = """
    if x == nil do
      {:error, :missing}
    elsif y <= 0 do
      {:error, :invalid}
    else
      {:ok, y}
    end
    """

    assert [%Issue{rule: :no_elsif_keyword} | _] = analyze(input)
  end

  test "reports one issue per elsif" do
    input = """
    if x == nil do
      {:error, :missing}
    elsif y <= 0 do
      {:error, :invalid}
    elsif y > 100 do
      {:error, :too_large}
    else
      {:ok, y}
    end
    """

    assert [%Issue{rule: :no_elsif_keyword}, %Issue{rule: :no_elsif_keyword}] = analyze(input)
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
