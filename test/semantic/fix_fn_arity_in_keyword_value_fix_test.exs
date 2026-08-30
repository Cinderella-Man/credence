defmodule Credence.Semantic.FixFnArityInKeywordValueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixFnArityInKeywordValue

  @real_diag_msg "incompatible types given to Kernel.//2:\n\n    :push / 4\n\ngiven types:\n\n    -:push-, integer()\n\nbut expected one of:\n\n    float() or integer(), float() or integer()\n"

  # `line` must be the line of the flagged `/` expression — the fix is
  # anchored to the diagnostic's line.
  defp fix(source, line) do
    FixFnArityInKeywordValue.fix(source, %{
      severity: :warning,
      message: @real_diag_msg,
      position: {line, 1}
    })
  end

  test "fixes the flagship input" do
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

    confirm_fix(fix(input, 4), expected)
  end

  test "dispatches the compiler's diagnostic through the semantic pipeline" do
    input = """
    defmodule FixFnAritySemanticPipelineFixture do
      def push(_value) do
        raise FunctionClauseError, function: :push/4
      end
    end
    """

    expected = """
    defmodule FixFnAritySemanticPipelineFixture do
      def push(_value) do
        raise FunctionClauseError, function: :push, arity: 4
      end
    end
    """

    {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)

    assert Enum.any?(
             diagnostics,
             &(&1.severity == :warning and &1.message == @real_diag_msg and
                 FixFnArityInKeywordValue.match?(&1))
           )

    confirm_fix(Credence.Semantic.fix(input), expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "fixes UndefinedFunctionError the same way" do
    input = """
    defmodule UndefinedFnArityExample do
      def call(mod) do
        raise UndefinedFunctionError, function: :run/0
      end
    end
    """

    expected = """
    defmodule UndefinedFnArityExample do
      def call(mod) do
        raise UndefinedFunctionError, function: :run, arity: 0
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "preserves surrounding keyword pairs" do
    input = """
    defmodule MultiPairExample do
      def push(value) do
        raise FunctionClauseError, module: __MODULE__, function: :push/4, kind: :def
      end
    end
    """

    expected = """
    defmodule MultiPairExample do
      def push(value) do
        raise FunctionClauseError, module: __MODULE__, function: :push, arity: 4, kind: :def
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "replaces a later arity option instead of leaving a winning duplicate" do
    input = """
    defmodule DuplicateFnArityExample do
      def push(value) do
        raise FunctionClauseError, function: :push/4, arity: 3
      end
    end
    """

    expected = """
    defmodule DuplicateFnArityExample do
      def push(value) do
        raise FunctionClauseError, function: :push, arity: 4
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "does not rewrite a matching raise inside quote on the diagnostic line" do
    input = """
    defmodule QuotedFnArityExample do
      def push(value) do
        raise FunctionClauseError, function: :push/4; quote do: (raise FunctionClauseError, function: :other/2)
      end
    end
    """

    expected = """
    defmodule QuotedFnArityExample do
      def push(value) do
        raise FunctionClauseError, function: :push, arity: 4
        quote do: raise(FunctionClauseError, function: :other / 2)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "no-op: exception struct without function/arity fields (ArgumentError)" do
    input = """
    defmodule OtherException do
      def broken do
        raise ArgumentError, function: :push/4
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "no-op: numerator is a variable, not an atom literal" do
    input = """
    defmodule VarNumerator do
      def broken(name) do
        raise FunctionClauseError, function: name/4
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "no-op: arity is a variable, not an integer literal" do
    input = """
    defmodule VarArity do
      def broken(n) do
        raise FunctionClauseError, function: :push/n
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "no-op: negative arity literal" do
    input = """
    defmodule NegativeArity do
      def broken do
        raise FunctionClauseError, function: :push/-1
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "no-op: diagnostic points at a different line than the raise" do
    input = """
    defmodule ElsewhereDiag do
      def broken do
        _ = :a / 2
        raise FunctionClauseError, function: :push/4
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "fixed output is well-formed and compiles" do
    input = """
    defmodule FixFnArityCompiles do
      def push(value) do
        raise FunctionClauseError, function: :push/4
      end
    end
    """

    assert valid_syntax?(fix(input, 3))
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(fix(input, 3))
  end
end
