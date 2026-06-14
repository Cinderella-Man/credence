defmodule Credence.Semantic.PreferEnumJoinFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferEnumJoin

  @real_message "String.join/2 is undefined or private"

  defp fix(source, line) do
    PreferEnumJoin.fix(source, %{severity: :warning, message: @real_message, position: {line, 1}})
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

    confirm_fix(fix(input, 3), expected)
  end

  test "only rewrites the flagged line" do
    input = """
    defmodule Solution do
      def a(list), do: String.join(list, "")
      def b(list), do: String.join(list, "")
    end
    """

    expected = """
    defmodule Solution do
      def a(list), do: Enum.join(list, "")
      def b(list), do: String.join(list, "")
    end
    """

    confirm_fix(fix(input, 2), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      def check_string_equality(list_a, list_b) do
        String.join(list_a, "") == String.join(list_b, "")
      end
    end
    """

    assert valid_syntax?(fix(input, 3))
  end

  describe "integration through Credence.Semantic" do
    test "fixes String.join end-to-end and the result compiles clean" do
      source = """
      defmodule EnumJoinFixInteg1 do
        def render(list), do: String.join(list, ", ")
      end
      """

      expected = """
      defmodule EnumJoinFixInteg1 do
        def render(list), do: Enum.join(list, ", ")
      end
      """

      fixed = Credence.Semantic.fix(source)
      confirm_fix(fixed, expected)
      assert valid_syntax?(fixed)
    end

    test "leaves correct Enum.join code untouched" do
      source = """
      defmodule EnumJoinFixInteg2 do
        def render(list), do: Enum.join(list, ", ")
      end
      """

      confirm_fix(Credence.Semantic.fix(source), source)
    end
  end
end
