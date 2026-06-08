defmodule Credence.FixExamplesTest do
  @moduledoc """
  Five additional realistic LLM-generated modules put through Credence.fix/2.
  Each exercises a different combination of rules. Each example pins the FULL
  fixed module with a whole-string `==` compare.
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

  @fizzbuzz_fixed ~S"""
  defmodule FizzBuzz do
    @moduledoc "Generates FizzBuzz sequences."
    @doc "Returns a FizzBuzz list for the given range."
    def generate(n) do
      Enum.map_join(1..n, ", ", fn x -> fizz_or_buzz(x) end)
    end

    def divisible?(n, d), do: rem(n, d) == 0

    defp fizz_or_buzz(n) do
      cond do
        divisible?(n, 15) -> "FizzBuzz"
        divisible?(n, 3) -> "Fizz"
        divisible?(n, 5) -> "Buzz"
        true -> Integer.to_string(n)
      end
    end
  end
  """

  describe "Example 1: FizzBuzz" do
    test "fully fixed output" do
      assert Credence.fix(@fizzbuzz_input, []).code == @fizzbuzz_fixed
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

  @caesar_fixed ~S"""
  defmodule CaesarCipher do
    @moduledoc "Simple Caesar cipher encryption and decryption."

    def encrypt(text, shift) do
      String.graphemes(text) |> Enum.map_join(fn c -> shift_char(c, shift) end)
    end

    def decrypt(text, shift) do
      String.graphemes(text) |> Enum.map_join(fn c -> shift_char(c, -shift) end)
    end

    def letter?(char) do
      String.match?(char, ~r/[a-zA-Z]/)
    end

    defp shift_char(char, shift) do
      if letter?(char) do
        base = if char >= "a" and char <= "z", do: ?a, else: ?A
        <<rem(hd(String.to_charlist(char)) - base + shift + 26, 26) + base>>
      else
        char
      end
    end
  end
  """

  describe "Example 2: Caesar Cipher" do
    test "fully fixed output" do
      assert Credence.fix(@caesar_input, []).code == @caesar_fixed
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

  @stats_fixed ~S"""
  defmodule Stats do
    @moduledoc "Basic statistical functions."

    def summarize(nums) do
      if nums == [] do
        :empty
      else
        sorted = Enum.sort(nums, :desc)
        max_val = Enum.at(sorted, 0)
        min_val = List.last(sorted)
        total = Enum.sum(nums)
        mean = :erlang.float(total / Enum.count(nums))
        %{max: max_val, min: min_val, mean: mean, count: Enum.count(nums)}
      end
    end
  end
  """

  describe "Example 3: Stats" do
    test "fully fixed output" do
      assert Credence.fix(@stats_input, []).code == @stats_fixed
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

  @ranker_fixed ~S"""
  defmodule WordRanker do
    @doc "Ranks words by frequency, returns top n."
    def top_words(text, n) do
      words = text |> String.downcase() |> String.split(~r/\W+/u, trim: true)

      freq = Enum.frequencies(words)

      freq
      |> Map.to_list()
      |> Enum.sort_by(fn {_word, count} -> count end)
      |> Enum.reverse()
      |> Enum.take(n)
    end

    def common_word?(word) do
      word |> String.downcase() |> Kernel.in(["the", "a", "an", "is", "of", "to"])
    end
  end
  """

  describe "Example 4: Word Ranker" do
    test "fully fixed output" do
      assert Credence.fix(@ranker_input, []).code == @ranker_fixed
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

  @toolkit_fixed ~S"""
  defmodule ListToolkit do
    @moduledoc "Utility functions for list manipulation."

    def unique_sorted(list) do
      list |> Enum.uniq() |> Enum.sort()
    end

    def char_count(text) do
      String.length(text)
    end

    defp do_flatten([], acc), do: Enum.reverse(acc)
    defp do_flatten([h | t], acc) when is_list(h), do: do_flatten(h ++ t, acc)
    defp do_flatten([h | t], acc), do: do_flatten(t, [h | acc])
  end
  """

  describe "Example 5: List Toolkit" do
    test "fully fixed output" do
      assert Credence.fix(@toolkit_input, []).code == @toolkit_fixed
    end
  end
end
