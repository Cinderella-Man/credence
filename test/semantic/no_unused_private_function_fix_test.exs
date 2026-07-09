defmodule Credence.Semantic.NoUnusedPrivateFunctionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnusedPrivateFunction

  defp fix(source, message, line \\ 1) do
    NoUnusedPrivateFunction.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  @unused_msg "function unused_helper/0 is unused"

  test "removes a single unused defp" do
    input = """
    defmodule M do
      def hello, do: :world
      defp unused_helper, do: :never_called
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @unused_msg), expected)
  end

  test "removes a multi-line unused defp" do
    input = """
    defmodule M do
      def hello, do: :world

      defp unused_helper do
        :never_called
      end
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "function unused_helper/0 is unused"), expected)
  end

  test "removes unused defp with arguments" do
    input = """
    defmodule M do
      def hello, do: :world
      defp add(a, b), do: a + b
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "function add/2 is unused"), expected)
  end

  test "removes all clauses of a multi-clause unused defp" do
    input = """
    defmodule M do
      def hello, do: :world
      defp helper(0), do: 0
      defp helper(n), do: n + 1
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "function helper/1 is unused"), expected)
  end

  test "removes a recursive but externally unused defp" do
    input = """
    defmodule M do
      def hello, do: :world
      defp count(0), do: 0
      defp count(n), do: count(n - 1)
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "function count/1 is unused"), expected)
  end

  test "leaves source unchanged when defp is called from a public function" do
    input = """
    defmodule M do
      def hello, do: helper()
      defp helper, do: :world
    end
    """

    confirm_fix(fix(input, @unused_msg), input)
  end

  test "leaves source unchanged when defp is called from quote block" do
    input = """
    defmodule M do
      defmacro my_macro do
        quote do
          helper()
        end
      end

      defp helper, do: :world
    end
    """

    confirm_fix(fix(input, @unused_msg), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def hello, do: :world
      defp unused_helper, do: :never_called
    end
    """

    assert valid_syntax?(fix(input, @unused_msg))
  end

  test "returns source unchanged for unrelated message" do
    input = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "unrelated warning"), input)
  end
end
