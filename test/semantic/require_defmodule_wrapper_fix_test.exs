defmodule Credence.Semantic.RequireDefmoduleWrapperFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.RequireDefmoduleWrapper

  defp fix(source, message, line \\ 1) do
    RequireDefmoduleWrapper.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    @doc \"""
    Returns the smallest number in a non-empty list of numbers.
    \"""
    @spec smallest_num([number()]) :: number()
    def smallest_num([head | tail]) do
      smallest_num(tail, head)
    end
    """

    expected = """
    defmodule Solution do
    @doc \"""
    Returns the smallest number in a non-empty list of numbers.
    \"""
    @spec smallest_num([number()]) :: number()
    def smallest_num([head | tail]) do
      smallest_num(tail, head)
    end
    end
    """

    message = "cannot invoke @doc/1 outside module"
    assert fix(input, message) == expected
  end

  test "fixed output is well-formed (parses)" do
    message = "cannot invoke @doc/1 outside module"

    assert valid_syntax?(
             fix(
               """
               @doc \"""
               Returns the smallest number in a non-empty list of numbers.
               \"""
               @spec smallest_num([number()]) :: number()
               def smallest_num([head | tail]) do
                 smallest_num(tail, head)
               end
               """,
               message
             )
           )
  end

  test "moves doc/spec attrs orphaned ABOVE an existing module INTO it" do
    input = """
    @moduledoc "Greets"
    defmodule Greeter do
      def hi, do: :ok
    end
    """

    expected = """
    defmodule Greeter do
      @moduledoc "Greets"
      def hi, do: :ok
    end
    """

    # The message is passed INLINE (not via a var) on purpose: it exercises the
    # FixtureStringEscaping meta-test fix — a diagnostic-message arg to a
    # source-first verb is NOT a code fixture and must not be flagged.
    assert fix(input, "cannot invoke @/1 outside module") == expected
    assert valid_syntax?(fix(input, "cannot invoke @/1 outside module"))
  end

  test "declines (no-op) when a module exists but nothing movable precedes it" do
    input = """
    defmodule Greeter do
      def hi, do: :ok
    end

    @doc "orphan after the module"
    """

    assert fix(input, "cannot invoke @/1 outside module") == input
  end

  test "drops incoming @doc when module already has @doc" do
    input = """
    @doc \"""
    Validates whether a given string is a valid IPv4 address.
    \"""
    defmodule Solution do
      @doc \"""
      Checks if the given string is a valid IPv4 address.
      \"""
      def valid_ip?(address), do: true
    end
    """

    expected = """
    defmodule Solution do
      @doc \"""
      Checks if the given string is a valid IPv4 address.
      \"""
      def valid_ip?(address), do: true
    end
    """

    diag_message = "redefining @doc attribute previously set at line 2"
    result = fix(input, diag_message)
    assert result == expected
    assert valid_syntax?(result)
  end

  test "drops inner @moduledoc false when moving real @moduledoc into module" do
    input = """
    @moduledoc \"""
    Solution module for counting distinct non-empty subsequences.
    \"""

    defmodule Solution do
      @moduledoc false

      @spec number_of_distinct_subsequences(String.t()) :: non_neg_integer()
      def number_of_distinct_subsequences(string) when is_binary(string) do
        mod = 1_000_000_007
        {total, _last_seen} =
          String.graphemes(string)
          |> Enum.reduce({1, %{}}, fn grapheme, {total_count, last_seen} ->
            new_total = rem(total_count * 2, mod)
            case Map.get(last_seen, grapheme) do
              nil ->
                new_last_seen = Map.put(last_seen, grapheme, total_count)
                {new_total, new_last_seen}
              prev_total ->
                corrected_total = rem(new_total - prev_total, mod)
                new_last_seen = Map.put(last_seen, grapheme, total_count)
                {corrected_total, new_last_seen}
            end
          end)
        result = rem(total - 1, mod)
        if result < 0, do: result + mod, else: result
      end
    end
    """

    expected = """
    defmodule Solution do
      @moduledoc \"""
      Solution module for counting distinct non-empty subsequences.
      \"""

      @spec number_of_distinct_subsequences(String.t()) :: non_neg_integer()
      def number_of_distinct_subsequences(string) when is_binary(string) do
        mod = 1_000_000_007

        {total, _last_seen} =
          String.graphemes(string)
          |> Enum.reduce({1, %{}}, fn grapheme, {total_count, last_seen} ->
            new_total = rem(total_count * 2, mod)

            case Map.get(last_seen, grapheme) do
              nil ->
                new_last_seen = Map.put(last_seen, grapheme, total_count)
                {new_total, new_last_seen}

              prev_total ->
                corrected_total = rem(new_total - prev_total, mod)
                new_last_seen = Map.put(last_seen, grapheme, total_count)
                {corrected_total, new_last_seen}
            end
          end)

        result = rem(total - 1, mod)
        if result < 0, do: result + mod, else: result
      end
    end
    """

    diag_message = "redefining @moduledoc attribute previously set at line 2"
    result = fix(input, diag_message)
    assert result == expected
    assert valid_syntax?(result)
    # Verify @moduledoc false is gone
    refute result =~ "@moduledoc false"
  end
end