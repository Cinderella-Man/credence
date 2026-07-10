defmodule Credence.Semantic.PreferDoubleQuotedAtomFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferDoubleQuotedAtom

  @real_message "using single-quoted strings to represent charlists is deprecated.\nUse ~c\"\" if you indeed want a charlist or use \"\" instead.\nYou may run \"mix format --migrate\" to change all single-quoted\nstrings to use the ~c sigil and fix this warning."

  defp fix(source, message \\ @real_message, line \\ 4) do
    PreferDoubleQuotedAtom.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes single-quoted atom in case clause" do
    input = """
    defmodule Example do
      def first_key do
        case :ets.first(:my_table) do
          :'$end_of_table' ->
            :empty

          key ->
            {:ok, key}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def first_key do
        case :ets.first(:my_table) do
          :"$end_of_table" ->
            :empty

          key ->
            {:ok, key}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def first_key do
        case :ets.first(:my_table) do
          :'$end_of_table' ->
            :empty

          key ->
            {:ok, key}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no single-quoted atoms" do
    input = """
    defmodule Clean do
      def first_key do
        case :ets.first(:my_table) do
          :"$end_of_table" ->
            :empty

          key ->
            {:ok, key}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixes multiple single-quoted atoms" do
    input = """
    defmodule Multi do
      def check do
        :'$end_of_table'
        :'$bad_atom'
      end
    end
    """

    expected = """
    defmodule Multi do
      def check do
        :"$end_of_table"
        :"$bad_atom"
      end
    end
    """

    confirm_fix(fix(input), expected)
  end
end
