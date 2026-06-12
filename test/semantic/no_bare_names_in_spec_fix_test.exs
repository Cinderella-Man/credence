defmodule Credence.Semantic.NoBareNamesInSpecFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.NoBareNamesInSpec

  @diagnostic %{
    message: "credence_check.ex:2: type sub_list/0 undefined (no such type in Solution)",
    position: 2,
    file: "credence_check.ex",
    severity: :error
  }

  defp fix(source, diagnostic \\ @diagnostic) do
    NoBareNamesInSpec.fix(source, diagnostic)
  end

  test "fixes bare name in spec" do
    input = """
    defmodule Solution do
      @spec countsubarray(list, sub_list) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec countsubarray(list, sub_list :: any()) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    assert fix(input) == expected
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      @spec countsubarray(list, sub_list) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fixed output compiles" do
    input = """
    defmodule Solution do
      @spec countsubarray(list, sub_list) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    assert Credence.RuleCase.compiles?(fix(input))
  end

  test "returns source unchanged when no bare name matches" do
    input = """
    defmodule Solution do
      @spec countsubarray(list, sub_list :: any()) :: non_neg_integer()
      def countsubarray(list, sub_list) when is_list(list) and is_list(sub_list) do
        length(list) + length(sub_list)
      end
    end
    """

    assert fix(input) == input
  end

  test "handles different bare names" do
    diagnostic = %{
      message: "credence_check.ex:2: type my_param/0 undefined (no such type in MyMod)",
      position: 2,
      file: "credence_check.ex",
      severity: :error
    }

    input = """
    defmodule MyMod do
      @spec foo(my_param) :: integer()
      def foo(x), do: x
    end
    """

    expected = """
    defmodule MyMod do
      @spec foo(my_param :: any()) :: integer()
      def foo(x), do: x
    end
    """

    assert fix(input, diagnostic) == expected
  end
end
