defmodule Credence.Pattern.NoDuplicateFunctionClausesFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDuplicateFunctionClauses

  test "removes duplicate clause" do
    input = """
    defmodule Example do
      def bar(x, y), do: {x, y}
      def bar(x, y), do: {x, y}
    end
    """

    expected = """
    defmodule Example do
      def bar(x, y) do
        {x, y}
      end
    end
    """

    assert fix(NoDuplicateFunctionClauses, input) == expected
  end

  test "removes multiple duplicate clauses" do
    input = """
    defmodule Example do
      def bar(x, y), do: {x, y}
      def bar(x, y), do: {x, y}
      def bar(x, y), do: {x, y}
    end
    """

    expected = """
    defmodule Example do
      def bar(x, y) do
        {x, y}
      end
    end
    """

    assert fix(NoDuplicateFunctionClauses, input) == expected
  end

  test "removes duplicate with different variable names" do
    input = """
    defmodule Example do
      def bar(x, y), do: {x, y}
      def bar(a, b), do: {a, b}
    end
    """

    expected = """
    defmodule Example do
      def bar(x, y) do
        {x, y}
      end
    end
    """

    assert fix(NoDuplicateFunctionClauses, input) == expected
  end

  test "leaves code without duplicates unchanged" do
    code = """
    defmodule Good do
      def bar(x, y), do: {x, y}
    end
    """

    assert fix(NoDuplicateFunctionClauses, code) == code
  end

  test "leaves different function names unchanged" do
    code = """
    defmodule Good do
      def bar(x, y), do: {x, y}
      def baz(x, y), do: {x, y}
    end
    """

    assert fix(NoDuplicateFunctionClauses, code) == code
  end

  test "leaves different arities unchanged" do
    code = """
    defmodule Good do
      def bar(x), do: x
      def bar(x, y), do: {x, y}
    end
    """

    assert fix(NoDuplicateFunctionClauses, code) == code
  end

  test "leaves clauses with different patterns unchanged" do
    code = """
    defmodule Good do
      def bar(0, y), do: {:zero, y}
      def bar(x, y), do: {x, y}
    end
    """

    assert fix(NoDuplicateFunctionClauses, code) == code
  end
end
