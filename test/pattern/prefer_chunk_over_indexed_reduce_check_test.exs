defmodule Credence.Pattern.PreferChunkOverIndexedReduceCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferChunkOverIndexedReduce

  test "flags the anti-pattern" do
    code = """
    list
    |> Stream.with_index()
    |> Enum.reduce(0, fn {value, index}, acc ->
      cond do
        index == 0 ->
          if value > Enum.at(list, 1) do
            acc + 1
          else
            acc
          end

        index == length(list) - 1 ->
          if value > Enum.at(list, index - 1) do
            acc + 1
          else
            acc
          end

        true ->
          left = Enum.at(list, index - 1)
          right = Enum.at(list, index + 1)

          if value > left and value > right do
            acc + 1
          else
            acc
          end
      end
    end)
    """

    assert flagged?(PreferChunkOverIndexedReduce, code)
  end

  test "leaves good code alone" do
    code = "Enum.sum(list)"

    assert clean?(PreferChunkOverIndexedReduce, code)
  end
end
