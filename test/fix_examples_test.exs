defmodule Credence.FixExamplesTest do
  @moduledoc """
  Five additional realistic LLM-generated modules put through Credence.fix/2.
  Each exercises a different combination of rules.
  """
  use ExUnit.Case

  # ═══════════════════════════════════════════════════════════════════
  # Example 1: FizzBuzz — naming, doc, map_join
  # ═══════════════════════════════════════════════════════════════════

  @fizzbuzz_input ~S"""
  defmodule FizzBuzz do
    @moduledoc "Generates FizzBuzz sequences.\n"
    @doc "Returns a FizzBuzz list for the given range.\n"
    def generate(n) do
      Enum.map(1..n, fn x -> fizz_or_buzz(x) end) |> Enum.join(", ")
    end

    def is_divisible(n, d), do: rem(n, d) == 0

    @doc false
    defp fizz_or_buzz(n) do
      cond do
        is_divisible(n, 15) -> "FizzBuzz"
        is_divisible(n, 3) -> "Fizz"
        is_divisible(n, 5) -> "Buzz"
        true -> Integer.to_string(n)
      end
    end
  end
  """

  describe "Example 1: FizzBuzz" do
    setup do
      %{result: Credence.fix(@fizzbuzz_input, [])}
    end

    test "output is valid Elixir", %{result: %{code: code}} do
      assert {:ok, _} = Code.string_to_quoted(code)
    end

    test "strips trailing \\n from @moduledoc", %{result: %{code: code}} do
      assert code =~ ~S|@moduledoc "Generates FizzBuzz sequences."|
      refute code =~ ~S|sequences.\n"|
    end

    test "strips trailing \\n from @doc", %{result: %{code: code}} do
      refute code =~ ~S|range.\n"|
    end

    test "fuses Enum.map |> Enum.join into Enum.map_join", %{result: %{code: code}} do
      assert code =~ "Enum.map_join"
      refute Regex.match?(~r/Enum\.map\(.*\) \|> Enum\.join/, code)
    end

    test "renames is_divisible to divisible?", %{result: %{code: code}} do
      assert code =~ "divisible?"
      refute code =~ "is_divisible"
    end

    test "removes @doc false on defp", %{result: %{code: code}} do
      refute code =~ "@doc false"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Example 2: Caesar Cipher — graphemes, manual reverse, join("")
  # ═══════════════════════════════════════════════════════════════════

  @caesar_input ~S"""
  defmodule CaesarCipher do
    @moduledoc "Simple Caesar cipher encryption and decryption.\n"

    def encrypt(text, shift) do
      String.graphemes(text) |> Enum.map(fn c -> shift_char(c, shift) end) |> Enum.join("")
    end

    def decrypt(text, shift) do
      String.graphemes(text) |> Enum.map(fn c -> shift_char(c, -shift) end) |> Enum.join("")
    end

    def is_letter(char) do
      String.match?(char, ~r/[a-zA-Z]/)
    end

    defp shift_char(char, shift) do
      if is_letter(char) do
        base = if char >= "a" and char <= "z", do: ?a, else: ?A
        <<rem(hd(String.to_charlist(char)) - base + shift + 26, 26) + base>>
      else
        char
      end
    end
  end
  """

  describe "Example 2: Caesar Cipher" do
    setup do
      %{result: Credence.fix(@caesar_input, [])}
    end

    test "output is valid Elixir", %{result: %{code: code}} do
      assert {:ok, _} = Code.string_to_quoted(code)
    end

    test "strips trailing \\n from @moduledoc", %{result: %{code: code}} do
      refute code =~ ~S|decryption.\n"|
    end

    test "removes redundant empty string from Enum.join", %{result: %{code: code}} do
      refute code =~ ~S|Enum.join("")|
    end

    test "renames is_letter to letter?", %{result: %{code: code}} do
      assert code =~ "letter?"
      refute code =~ "is_letter"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Example 3: Stats — sort+reverse, negative index, count, * 1.0
  # ═══════════════════════════════════════════════════════════════════

  @stats_input ~S"""
  defmodule Stats do
    @moduledoc "Basic statistical functions.\n"

    def summarize(nums) do
      if length(nums) == 0 do
        :empty
      else
        sorted = Enum.sort(nums) |> Enum.reverse()
        max_val = Enum.at(sorted, 0)
        min_val = Enum.at(sorted, -1)
        total = Enum.map(nums, fn n -> n end) |> Enum.sum()
        mean = total / Enum.count(nums) * 1.0
        %{max: max_val, min: min_val, mean: mean, count: Enum.count(nums)}
      end
    end
  end
  """

  describe "Example 3: Stats" do
    setup do
      %{result: Credence.fix(@stats_input, [])}
    end

    test "output is valid Elixir", %{result: %{code: code}} do
      assert {:ok, _} = Code.string_to_quoted(code)
    end

    test "replaces length(nums) == 0 with nums == []", %{result: %{code: code}} do
      assert code =~ "nums == []"
      refute code =~ "length(nums) == 0"
    end

    test "replaces Enum.sort |> Enum.reverse with Enum.sort(:desc)", %{result: %{code: code}} do
      assert code =~ "Enum.sort(nums, :desc)"
      refute code =~ "Enum.sort(nums) |> Enum.reverse()"
    end

    test "replaces Enum.count with length", %{result: %{code: code}} do
      assert code =~ "length(nums)"
      refute code =~ "Enum.count(nums)"
    end

    test "removes * 1.0", %{result: %{code: code}} do
      refute code =~ "* 1.0"
    end

    test "strips trailing \\n from @moduledoc", %{result: %{code: code}} do
      refute code =~ ~S|functions.\n"|
    end

    test "simplifies Enum.map identity |> Enum.sum", %{result: %{code: code}} do
      refute code =~ "Enum.map(nums, fn n -> n end)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Example 4: Word Ranker — frequencies, sort+take(-n), kernel op
  # ═══════════════════════════════════════════════════════════════════

  @ranker_input ~S"""
  defmodule WordRanker do
    @doc "Ranks words by frequency, returns top n.\n"
    def top_words(text, n) do
      words = text |> String.downcase() |> String.split(~r/\W+/u, trim: true)

      freq = Enum.reduce(words, %{}, fn word, acc ->
        Map.update(acc, word, 1, &(&1 + 1))
      end)

      freq
      |> Map.to_list()
      |> Enum.sort_by(fn {_word, count} -> count end)
      |> Enum.reverse()
      |> Enum.take(n)
    end

    def is_common_word(word) do
      word |> String.downcase() |> Kernel.in(["the", "a", "an", "is", "of", "to"])
    end
  end
  """

  describe "Example 4: Word Ranker" do
    setup do
      %{result: Credence.fix(@ranker_input, [])}
    end

    test "output is valid Elixir", %{result: %{code: code}} do
      assert {:ok, _} = Code.string_to_quoted(code)
    end

    test "replaces manual frequency reduce with Enum.frequencies", %{result: %{code: code}} do
      assert code =~ "Enum.frequencies"
      refute code =~ "Map.update(acc"
    end

    test "strips trailing \\n from @doc", %{result: %{code: code}} do
      refute code =~ ~S|top n.\n"|
    end

    test "renames is_common_word to common_word?", %{result: %{code: code}} do
      assert code =~ "common_word?"
      refute code =~ "is_common_word"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Example 5: List Toolkit — append in recursion, @doc false, uniq_by
  # ═══════════════════════════════════════════════════════════════════

  @toolkit_input ~S"""
  defmodule ListToolkit do
    @moduledoc "Utility functions for list manipulation.\n"

    def unique_sorted(list) do
      list |> Enum.uniq_by(fn x -> x end) |> Enum.sort()
    end

    def char_count(text) do
      String.graphemes(text) |> length()
    end

    @doc false
    defp do_flatten([], acc), do: Enum.reverse(acc)
    defp do_flatten([h | t], acc) when is_list(h), do: do_flatten(h ++ t, acc)
    defp do_flatten([h | t], acc), do: do_flatten(t, acc ++ [h])
  end
  """

  describe "Example 5: List Toolkit" do
    setup do
      result = Credence.fix(@toolkit_input, [])
      %{result: result}
    end

    test "output is valid Elixir", %{result: %{code: code}} do
      assert {:ok, _} = Code.string_to_quoted(code)
    end

    test "strips trailing \\n from @moduledoc", %{result: %{code: code}} do
      refute code =~ ~S|manipulation.\n"|
    end

    test "simplifies Enum.uniq_by identity to Enum.uniq", %{result: %{code: code}} do
      assert code =~ "Enum.uniq()"
      refute code =~ "Enum.uniq_by"
    end

    test "replaces String.graphemes |> length with String.length", %{result: %{code: code}} do
      assert code =~ "String.length(text)"
      refute code =~ "String.graphemes(text) |> length()"
    end

    test "removes @doc false on defp", %{result: %{code: code}} do
      refute code =~ "@doc false"
    end

    test "fixes list append in recursion to prepend", %{result: %{code: code}} do
      assert code =~ "[h | acc]"
      refute code =~ "acc ++ [h]"
    end
  end
end
