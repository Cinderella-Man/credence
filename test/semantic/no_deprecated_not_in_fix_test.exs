defmodule Credence.Semantic.NoDeprecatedNotInFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDeprecatedNotIn

  @real_message "\"not expr1 in expr2\" is deprecated, use \"expr1 not in expr2\" instead"

  defp fix(source, message \\ @real_message, line \\ 3) do
    NoDeprecatedNotIn.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "rewrites `not &1 in present_keys` to `&1 not in present_keys`" do
    input = """
    defmodule DepNotIn do
      def filter_missing(keys, present_keys) do
        Enum.filter(keys, &(not &1 in present_keys))
      end
    end
    """

    expected = """
    defmodule DepNotIn do
      def filter_missing(keys, present_keys) do
        Enum.filter(keys, &(&1 not in present_keys))
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "rewrites `not x in list` to `x not in list`" do
    input = """
    defmodule Example do
      def check(x, list) do
        not x in list
      end
    end
    """

    expected = """
    defmodule Example do
      def check(x, list) do
        x not in list
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "only rewrites the flagged line" do
    input = """
    defmodule Example do
      def a(x, y), do: not x in y
      def b(x, y), do: not x in y
    end
    """

    expected = """
    defmodule Example do
      def a(x, y), do: x not in y
      def b(x, y), do: not x in y
    end
    """

    confirm_fix(fix(input, @real_message, 2), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule DepNotIn do
      def filter_missing(keys, present_keys) do
        Enum.filter(keys, &(not &1 in present_keys))
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
