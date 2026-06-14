defmodule Credence.Semantic.PreferEnumJoinFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.PreferEnumJoin

  defp fix(source, message, line \\ 3) do
    PreferEnumJoin.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "fixes String.join to Enum.join" do
    input = """
    defmodule Solution do
      def check_string_equality(list_a, list_b) do
        String.join(list_a, "") == String.join(list_b, "")
      end
    end
    """

    expected = """
    defmodule Solution do
      def check_string_equality(list_a, list_b) do
        Enum.join(list_a, "") == Enum.join(list_b, "")
      end
    end
    """

    message =
      "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)"

    assert fix(input, message) == expected
  end

  test "fixed output is well-formed (parses)" do
    message =
      "redefining module Solution (current version loaded from _build/test/lib/workspace/ebin/Elixir.Solution.beam)"

    assert valid_syntax?(
             fix(
               """
               defmodule Solution do
                 def check_string_equality(list_a, list_b) do
                   String.join(list_a, "") == String.join(list_b, "")
                 end
               end
               """,
               message
             )
           )
  end
end
