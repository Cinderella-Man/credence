defmodule Credence.Semantic.NoBareNamesInSpecFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

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

    confirm_fix(fix(input), expected)
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

    confirm_fix(fix(input), input)
  end

  test "only rewrites the spec on the diagnostic line, never a same-named valid spec elsewhere" do
    # `sub_list` is undefined in module A (the line-2 spec the compiler rejects)
    # but is a *defined* type in module B, where `bar(sub_list)` is a perfectly
    # valid spec meaning "arg of type sub_list". Rewriting B's spec by name would
    # silently widen it to `:: any()`. The fix must touch only line 2.
    input = """
    defmodule A do
      @spec foo(sub_list) :: integer()
      def foo(x), do: x
    end

    defmodule B do
      @type sub_list :: [integer()]
      @spec bar(sub_list) :: integer()
      def bar(x), do: x
    end
    """

    diagnostic = %{
      message: "credence_check.ex:2: type sub_list/0 undefined (no such type in A)",
      position: 2,
      file: "credence_check.ex",
      severity: :error
    }

    expected = """
    defmodule A do
      @spec foo(sub_list :: any()) :: integer()
      def foo(x), do: x
    end

    defmodule B do
      @type sub_list :: [integer()]
      @spec bar(sub_list) :: integer()
      def bar(x), do: x
    end
    """

    confirm_fix(fix(input, diagnostic), expected)
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

    confirm_fix(fix(input, diagnostic), expected)
  end
end
