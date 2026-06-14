defmodule Credence.Pattern.NoBareValueInMapNewFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoBareValueInMapNew

  test "pairs the element with a list-literal value, de-underscoring the key" do
    input = """
    defmodule M do
      def f(n), do: Map.new(0..(n - 1), fn _k -> [] end)
    end
    """

    expected = """
    defmodule M do
      def f(n), do: Map.new(0..(n - 1), fn k -> {k, []} end)
    end
    """

    confirm_fix(fix(NoBareValueInMapNew, input), expected)
  end

  test "bare underscore param becomes `key`" do
    input = """
    defmodule M do
      def f(items), do: Map.new(items, fn _ -> %{} end)
    end
    """

    expected = """
    defmodule M do
      def f(items), do: Map.new(items, fn key -> {key, %{}} end)
    end
    """

    confirm_fix(fix(NoBareValueInMapNew, input), expected)
  end

  test "keeps a used parameter name as the key" do
    input = """
    defmodule M do
      def f(items), do: Map.new(items, fn item -> 0 end)
    end
    """

    expected = """
    defmodule M do
      def f(items), do: Map.new(items, fn item -> {item, 0} end)
    end
    """

    confirm_fix(fix(NoBareValueInMapNew, input), expected)
  end

  test "leaves a correct tuple-returning mapper unchanged" do
    input = """
    defmodule M do
      def f(keys), do: Map.new(keys, fn k -> {k, 0} end)
    end
    """

    confirm_fix(fix(NoBareValueInMapNew, input), input)
  end
end
