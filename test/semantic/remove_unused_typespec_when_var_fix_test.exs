defmodule Credence.Semantic.RemoveUnusedTypespecWhenVarFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.RemoveUnusedTypespecWhenVar

  defp fix(source, message, line \\ 2) do
    RemoveUnusedTypespecWhenVar.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
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

    message =
      "credence_check.ex:19: type variable var_ok is used only once. Type variables in typespecs must be referenced at least twice, otherwise it is equivalent to term()"

    assert fix(input, message) == expected
  end

  test "fixed output is well-formed (parses)" do
    message =
      "credence_check.ex:19: type variable var_ok is used only once. Type variables in typespecs must be referenced at least twice, otherwise it is equivalent to term()"

    assert valid_syntax?(
             fix(
               """
               defmodule Solution do
                 @spec foo(integer) :: integer when var_ok: true
                 def foo(x), do: x
               end
               """,
               message
             )
           )
  end
end
