defmodule Credence.Semantic.RemoveUnusedTypespecWhenVarFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.RemoveUnusedTypespecWhenVar

  defp diag(var, line) do
    %{
      severity: :error,
      message:
        "credence_check.ex:#{line}: type variable #{var} is used only once. Type variables in typespecs must be referenced at least twice, otherwise it is equivalent to term()",
      position: line,
      file: "credence_check.ex"
    }
  end

  defp fix(source, diagnostic), do: RemoveUnusedTypespecWhenVar.fix(source, diagnostic)

  test "drops the whole when clause when the unused var is its only binding" do
    input = """
    defmodule Solution do
      @spec foo(integer) :: integer when var_ok: true
      def foo(x), do: x
    end
    """

    expected = """
    defmodule Solution do
      @spec foo(integer) :: integer
      def foo(x), do: x
    end
    """

    confirm_fix(fix(input, diag("var_ok", 2)), expected)
  end

  test "drops only the unused binding, preserving sibling constraints" do
    input = """
    defmodule Solution do
      @spec foo(x) :: x when x: integer, var_ok: true
      def foo(x), do: x
    end
    """

    expected = """
    defmodule Solution do
      @spec foo(x) :: x when x: integer
      def foo(x), do: x
    end
    """

    confirm_fix(fix(input, diag("var_ok", 2)), expected)
  end

  test "drops a middle binding, keeping both surrounding constraints" do
    input = """
    defmodule Solution do
      @spec foo(a, b) :: {a, b} when a: integer, var_ok: true, b: atom
      def foo(x, y), do: {x, y}
    end
    """

    expected = """
    defmodule Solution do
      @spec foo(a, b) :: {a, b} when a: integer, b: atom
      def foo(x, y), do: {x, y}
    end
    """

    confirm_fix(fix(input, diag("var_ok", 2)), expected)
  end

  test "leaves other specs alone, fixing only the diagnostic line" do
    input = """
    defmodule Solution do
      @spec foo(integer) :: integer when keep_me: true
      def foo(x), do: x

      @spec bar(integer) :: integer when var_ok: true
      def bar(x), do: x
    end
    """

    expected = """
    defmodule Solution do
      @spec foo(integer) :: integer when keep_me: true
      def foo(x), do: x

      @spec bar(integer) :: integer
      def bar(x), do: x
    end
    """

    confirm_fix(fix(input, diag("var_ok", 5)), expected)
  end

  test "handles a when clause spread across multiple lines" do
    input = """
    defmodule Solution do
      @spec foo(x) :: x
            when x: integer,
                 var_ok: true
      def foo(x), do: x
    end
    """

    expected = """
    defmodule Solution do
      @spec foo(x) :: x
            when x: integer
      def foo(x), do: x
    end
    """

    confirm_fix(fix(input, diag("var_ok", 2)), expected)
  end

  test "returns source unchanged when the named var is not on the diagnostic line" do
    input = """
    defmodule Solution do
      @spec foo(integer) :: integer when keep_me: true
      def foo(x), do: x
    end
    """

    confirm_fix(fix(input, diag("var_ok", 2)), input)
  end

  test "fixed output is well-formed and compiles" do
    input = """
    defmodule Solution do
      @spec foo(x) :: x when x: integer, var_ok: true
      def foo(x), do: x
    end
    """

    assert valid_syntax?(fix(input, diag("var_ok", 2)))
    assert compiles?(fix(input, diag("var_ok", 2)))
  end
end
