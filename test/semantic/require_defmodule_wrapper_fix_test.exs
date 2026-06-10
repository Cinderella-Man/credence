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
end