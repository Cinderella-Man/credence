defmodule Credence.Pattern.PreferChunkOverIndexedReduceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferChunkOverIndexedReduce

  test "rewrites the anti-pattern" do
    input = """
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

    expected = """
    middle =
      list
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.count(fn [left, candidate, right] -> candidate > left and candidate > right end)

    first =
      case list do
        [first, second | _] when first > second -> 1
        _ -> 0
      end

    last =
      case Enum.reverse(list) do
        [last, second_last | _] when last > second_last -> 1
        _ -> 0
      end

    first + middle + last
    """

    assert fix(PreferChunkOverIndexedReduce, input) == expected
  end
end
