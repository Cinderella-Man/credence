defmodule Credence.Semantic.RequireDefmoduleWrapperFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

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
    confirm_fix(fix(input, message), expected)
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
    confirm_fix(fix(input, "cannot invoke @/1 outside module"), expected)
    # The repaired source must not just parse — it must actually compile (the
    # whole point of a semantic fix is to resolve the diagnostic).
    assert compiles?(fix(input, "cannot invoke @/1 outside module"))
  end

  # `move_attrs/1` builds the replacement block with the ROOT node's metadata,
  # and it only ever runs when `relocation/1` already matched the root as a
  # `{:__block__, _, children}`. These cases pin that every other root shape
  # (single statement, lone `defmodule`, unparseable source) reaches `fix/2`
  # without ever entering that branch — so no non-block root can get there.
  test "single-statement root (no block) wraps without entering the move branch" do
    input = ~S'@doc "x"'

    expected = """
    defmodule Solution do
    @doc "x"
    end
    """

    confirm_fix(fix(input, "cannot invoke @/1 outside module"), expected)
  end

  test "lone defmodule root (no block) is a no-op" do
    input = """
    defmodule A do
      def a, do: 1
    end
    """

    confirm_fix(fix(input, "cannot invoke @/1 outside module"), input)
  end

  test "unparseable source with no defmodule is wrapped, not crashed" do
    input = ~S'@doc "x'

    expected = """
    defmodule Solution do
    @doc "x
    end
    """

    confirm_fix(fix(input, "cannot invoke @/1 outside module"), expected)
  end

  test "moves attrs when a non-attr statement precedes them" do
    input = """
    import List
    @moduledoc "m"
    defmodule A do
      def a, do: 1
    end
    """

    expected = """
    import List
    defmodule A do
      @moduledoc "m"
      def a, do: 1
    end
    """

    confirm_fix(fix(input, "cannot invoke @/1 outside module"), expected)
  end

  test "moves attrs into the FIRST module when several modules follow" do
    input = """
    @doc "d"
    @spec f() :: :ok
    defmodule A do
      def f, do: :ok
    end

    defmodule B do
      def g, do: :ok
    end
    """

    expected = """
    defmodule A do
      @doc "d"
      @spec f() :: :ok
      def f, do: :ok
    end

    defmodule B do
      def g, do: :ok
    end
    """

    confirm_fix(fix(input, "cannot invoke @/1 outside module"), expected)
  end

  test "keeps an orphaned spec when the module specifies a different function" do
    input = """
    @spec first() :: :first
    defmodule RequireDefmoduleDistinctSpecTest do
      @spec second() :: :second
      def first, do: :first
      def second, do: :second
    end
    """

    expected = """
    defmodule RequireDefmoduleDistinctSpecTest do
      @spec first() :: :first
      @spec second() :: :second
      def first, do: :first
      def second, do: :second
    end
    """

    result = fix(input, "cannot invoke @/1 outside module")
    confirm_fix(result, expected)
    assert compiles?(result)
  end

  test "keeps an orphaned type when the module declares a different type" do
    input = """
    @type first() :: :first
    defmodule RequireDefmoduleDistinctTypeTest do
      @type second() :: :second
    end
    """

    expected = """
    defmodule RequireDefmoduleDistinctTypeTest do
      @type first() :: :first
      @type second() :: :second
    end
    """

    result = fix(input, "cannot invoke @/1 outside module")
    confirm_fix(result, expected)
    assert compiles?(result)
  end

  test "declines (no-op) when a module exists but nothing movable precedes it" do
    input = """
    defmodule Greeter do
      def hi, do: :ok
    end

    @doc "orphan after the module"
    """

    confirm_fix(fix(input, "cannot invoke @/1 outside module"), input)
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
    confirm_fix(result, expected)
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
    confirm_fix(result, expected)
    assert valid_syntax?(result)
    assert compiles?(result)
  end
end
