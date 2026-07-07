defmodule Credence.Semantic.FixFnArityInKeywordValueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixFnArityInKeywordValue

  @real_diag_msg "incompatible types given to Kernel.//2:\n\n    :push / 4\n\ngiven types:\n\n    -:push-, integer()\n\nbut expected one of:\n\n    float() or integer(), float() or integer()\n"

  defp fix(source, message, line \\ 1) do
    FixFnArityInKeywordValue.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    defmodule FixFnArityExample do
      def push(server, name, value, window_size) do
        unless is_number(value) do
          raise FunctionClauseError, function: :push/4
        end
        :ok
      end
    end
    """

    expected = """
    defmodule FixFnArityExample do
      def push(server, name, value, window_size) do
        unless is_number(value) do
          raise FunctionClauseError, function: :push, arity: 4
        end

        :ok
      end
    end
    """

    confirm_fix(fix(input, @real_diag_msg), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule FixFnArityExample do
      def push(server, name, value, window_size) do
        unless is_number(value) do
          raise FunctionClauseError, function: :push/4
        end
        :ok
      end
    end
    """

    assert valid_syntax?(fix(input, @real_diag_msg))
  end
end
