defmodule Credence.FixShowcaseTest do
  @moduledoc """
  End-to-end integration test: feeds a realistic LLM-generated module
  through Credence.fix/2 and verifies every transformation applied.
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

  setup do
    %{result: Credence.fix(@input, [])}
  end

  describe "Credence.fix/2 showcase — 19 anti-patterns in, idiomatic Elixir out" do
    # ── Doc formatting ──────────────────────────────────────────────

    test "strips trailing \\n from @moduledoc", %{result: %{code: code}} do
      assert code =~ ~S|@moduledoc "Provides text analysis utilities for processing and analyzing strings."|
      refute code =~ ~S|strings.\n"|
    end

    test "converts multi-line @doc to heredoc", %{result: %{code: code}} do
      assert code =~ ~S|@doc """|
      assert code =~ "  Analyzes the given text and returns a map of statistics."
      assert code =~ "  Returns word count, character count, average word length,"
    end

    # ── Emptiness & length checks ─────────────────────────────────

    test "replaces length(words) == 0 with words == []", %{result: %{code: code}} do
      assert code =~ "words == []"
      refute code =~ "length(words) == 0"
    end

    test "replaces String.graphemes |> length with String.length", %{result: %{code: code}} do
      assert code =~ "String.length(text)"
      refute code =~ "String.graphemes(text) |> length()"
    end

    test "replaces Enum.count(words) with length(words)", %{result: %{code: code}} do
      assert code =~ "length(words)"
      refute code =~ "Enum.count(words)"
    end

    # ── Arithmetic ────────────────────────────────────────────────

    test "removes * 1.0", %{result: %{code: code}} do
      refute code =~ "* 1.0"
    end

    # ── Collection operations ─────────────────────────────────────

    test "fuses Enum.map |> Enum.sum into Enum.reduce", %{result: %{code: code}} do
      assert code =~ "Enum.reduce(words, 0, fn el, acc -> acc + String.length(el) end)"
      refute code =~ "Enum.map(words, fn w -> String.length(w) end) |> Enum.sum()"
    end

    test "replaces manual frequency reduce with Enum.frequencies", %{result: %{code: code}} do
      assert code =~ "Enum.frequencies"
      refute code =~ "Map.update(acc"
    end

    test "replaces Enum.sort |> Enum.reverse with Enum.sort(:desc)", %{result: %{code: code}} do
      assert code =~ "Enum.sort(words, :desc)"
      refute code =~ "Enum.sort(words) |> Enum.reverse()"
    end

    test "replaces Enum.sort |> Enum.take(-3) with desc sort + positive take",
         %{result: %{code: code}} do
      assert code =~ "Enum.sort(words, :desc) |> Enum.take(3)"
      refute code =~ "Enum.take(-3)"
    end

    test "groups negative Enum.at calls into reverse + pattern match",
         %{result: %{code: code}} do
      assert code =~ "Enum.reverse(sorted_desc)"
      assert code =~ "[last, second_last | _]"
      refute code =~ "Enum.at(sorted_desc, -1)"
      refute code =~ "Enum.at(sorted_desc, -2)"
    end

    test "simplifies Enum.uniq_by(fn w -> w end) to Enum.uniq()", %{result: %{code: code}} do
      assert code =~ "Enum.uniq()"
      refute code =~ "Enum.uniq_by"
    end

    test "fuses Enum.map |> Enum.join into Enum.map_join", %{result: %{code: code}} do
      assert code =~ "Enum.map_join"
      refute Regex.match?(~r/Enum\.map\(.*\) \|> Enum\.join/, code)
    end

    # ── Naming & style ────────────────────────────────────────────

    test "renames is_palindrome to palindrome?", %{result: %{code: code}} do
      assert code =~ "def palindrome?(text)"
      assert code =~ "palindrome?(text)"
      refute code =~ "is_palindrome"
    end

    test "extracts Kernel.== from pipeline to infix", %{result: %{code: code}} do
      assert code =~ "cleaned == reversed"
      refute code =~ "Kernel.=="
    end

    test "replaces manual string reverse with String.reverse", %{result: %{code: code}} do
      assert code =~ "String.reverse(cleaned)"
      refute code =~ "String.graphemes(cleaned) |> Enum.reverse()"
    end

    test "removes @doc false on private function", %{result: %{code: code}} do
      refute code =~ "@doc false"
    end

    test "fixes list append in recursion to prepend", %{result: %{code: code}} do
      assert code =~ "[String.downcase(h) | acc]"
      refute code =~ "acc ++ [String.downcase(h)]"
    end

    # ── Remaining issues (expected) ───────────────────────────────

    test "only expected issues remain", %{result: %{issues: issues}} do
      rules = issues |> Enum.map(& &1.rule) |> Enum.sort()

      assert rules == [
               :no_sort_for_top_k_reduce,
               :no_sort_then_reverse
             ]
    end

    # ── Sanity ────────────────────────────────────────────────────

    test "output is valid Elixir", %{result: %{code: code}} do
      assert {:ok, _ast} = Code.string_to_quoted(code)
    end
  end
end
