defmodule Credence.Syntax.PreferRecursionOverWhileAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferRecursionOverWhile

  defp analyze(code), do: PreferRecursionOverWhile.analyze(code)

  test "flags a while loop" do
    assert [%Issue{rule: :prefer_recursion_over_while}] =
             analyze("""
             while idx < 10 do
               idx = idx + 1
             end
             """)
  end

  test "flags while loop inside a function" do
    issues =
      analyze("""
      defmodule Solution do
        def example(list) do
          result = []
          idx = 0
          while idx < length(list) do
            result = result ++ [Enum.at(list, idx)]
            idx = idx + 1
          end
          result
        end
      end
      """)

    assert [%Issue{rule: :prefer_recursion_over_while, meta: %{line: 5}}] = issues
  end

  test "leaves valid Elixir alone" do
    assert analyze("""
           def example(list) do
             Enum.each(list, fn x -> IO.puts(x) end)
           end
           """) == []
  end

  test "leaves code with do: keyword alone" do
    assert analyze("""
           if x, do: 1, else: 2
           """) == []
  end
end
