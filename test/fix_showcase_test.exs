defmodule Credence.FixShowcaseTest do
  @moduledoc """
  End-to-end integration test: feeds a realistic LLM-generated module
  through Credence.fix/2 and pins the full idiomatic output.
  """
  use ExUnit.Case

  @input ~S"""
  defmodule Solution do
    @moduledoc "Provides text analysis utilities for processing and analyzing strings.\n"
    @doc "Analyzes the given text and returns a map of statistics.\n\nReturns word count, character count, average word length,\nfrequency map, and other derived metrics.\n"
    @spec analyze(String.t()) :: map()
    def analyze(text) do
      words = String.split(text)

      if length(words) == 0 do
        %{words: 0, chars: 0, avg_length: 0.0}
      else
        char_count = String.graphemes(text) |> length()

        total_length = Enum.map(words, fn w -> String.length(w) end) |> Enum.sum()
        avg_length = total_length / Enum.count(words) * 1.0

        frequencies = Enum.reduce(words, %{}, fn word, acc ->
          Map.update(acc, String.downcase(word), 1, &(&1 + 1))
        end)

        sorted_desc = Enum.sort(words) |> Enum.reverse()
        top_3 = Enum.sort(words) |> Enum.take(-3)

        last = Enum.at(sorted_desc, -1)
        second_last = Enum.at(sorted_desc, -2)

        unique_words = words |> Enum.uniq_by(fn w -> w end)
        unique_csv = Enum.map(unique_words, fn w -> String.upcase(w) end) |> Enum.join(",")

        %{
          char_count: char_count,
          avg_length: avg_length,
          frequencies: frequencies,
          top_3: top_3,
          last: last,
          second_last: second_last,
          unique_csv: unique_csv,
          palindrome: is_palindrome(text)
        }
      end
    end

    def is_palindrome(text) do
      cleaned = text |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
      reversed = String.graphemes(cleaned) |> Enum.reverse() |> Enum.join("")
      cleaned |> Kernel.==(reversed)
    end

    @doc false
    defp normalize_words([], acc), do: Enum.reverse(acc)
    defp normalize_words([h | t], acc), do: normalize_words(t, acc ++ [String.downcase(h)])
  end
  """

  @expected ~S'''
  defmodule Solution do
    @moduledoc "Provides text analysis utilities for processing and analyzing strings."
    @doc """
    Analyzes the given text and returns a map of statistics.

    Returns word count, character count, average word length,
    frequency map, and other derived metrics.
    """
    @spec analyze(String.t()) :: map()
    def analyze(text) do
      words = String.split(text)

      if words == [] do
        %{words: 0, chars: 0, avg_length: 0.0}
      else
        char_count = String.length(text)

        total_length = Enum.reduce(words, 0, fn el, acc -> acc + String.length(el) end)
        avg_length = :erlang.float(total_length / Enum.count(words))

        frequencies =
          Enum.frequencies_by(words, fn word -> String.downcase(word) end)

        sorted_desc = Enum.sort(words, :desc)
        top_3 = Enum.sort(words, :desc) |> Enum.take(3) |> Enum.reverse()

        last = Enum.at(sorted_desc, -1)
        second_last = Enum.at(sorted_desc, -2)

        unique_words = words |> Enum.uniq()
        unique_csv = Enum.map_join(unique_words, ",", fn w -> String.upcase(w) end)

        %{
          char_count: char_count,
          avg_length: avg_length,
          frequencies: frequencies,
          top_3: top_3,
          last: last,
          second_last: second_last,
          unique_csv: unique_csv,
          palindrome: is_palindrome(text)
        }
      end
    end

    def is_palindrome(text) do
      cleaned = text |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
      reversed = String.reverse(cleaned)
      cleaned == reversed
    end

    defp normalize_words([], acc), do: Enum.reverse(acc)
    defp normalize_words([h | t], acc), do: normalize_words(t, [String.downcase(h) | acc])
  end
  '''

  setup do
    %{result: Credence.fix(@input, [])}
  end

  describe "Credence.fix/2 showcase — 19 anti-patterns in, idiomatic Elixir out" do
    test "fully fixed output", %{result: %{code: code}} do
      assert code == @expected
    end

    test "no issues remain after fix", %{result: %{issues: issues}} do
      # Project stance: every rule either auto-fixes its anti-pattern or it
      # doesn't exist. After Credence.fix/2, no outstanding issues should remain.
      assert issues |> Enum.map(& &1.rule) |> Enum.sort() == []
    end
  end
end
