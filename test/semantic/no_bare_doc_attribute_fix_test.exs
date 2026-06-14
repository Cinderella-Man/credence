defmodule Credence.Semantic.NoBareDocAttributeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoBareDocAttribute

  @message "module attribute @doc in code block has no effect"

  defp fix(source, line \\ 2) do
    NoBareDocAttribute.fix(source, %{severity: :warning, message: @message, position: {line, 1}})
  end

  test "removes bare @doc before def" do
    input = """
    defmodule Solution do
      @doc
      def calculate_total_cost(price) do
        price * 1.1
      end
    end
    """

    expected = """
    defmodule Solution do
      def calculate_total_cost(price) do
        price * 1.1
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not remove @doc with a string argument" do
    input = """
    defmodule Solution do
      @doc "Calculates total cost."
      def calculate_total_cost(price) do
        price * 1.1
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not remove @doc false" do
    input = """
    defmodule Solution do
      @doc false
      def calculate_total_cost(price) do
        price * 1.1
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not remove @doc with heredoc" do
    input = """
    defmodule Solution do
      @doc \"""
      Calculates total cost.
      \"""
      def calculate_total_cost(price) do
        price * 1.1
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @doc
               def calculate_total_cost(price) do
                 price * 1.1
               end
             end
             """)
           )
  end
end
