defmodule Credence.Semantic.NoPrivateFnCalledFromMacroQuoteFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoPrivateFnCalledFromMacroQuote

  defp fix(source, message, line \\ 1) do
    NoPrivateFnCalledFromMacroQuote.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "promotes defp to def with @doc false (multi-clause)" do
    input = """
    defmodule MacroWithHelper do
      defmacro validate(list, direction \\\\ :asc) do
        quote do
          list = unquote(list)
          direction = unquote(direction)

          case list do
            [] -> :ok
            [_] -> :ok
            _ -> check_order(list, direction, 0)
          end
        end
      end

      defp check_order([_], _dir, _idx), do: :ok

      defp check_order([_a, _b | _rest], :asc, _idx), do: :asc
      defp check_order([_a, _b | _rest], :desc, _idx), do: :desc
    end
    """

    expected = """
    defmodule MacroWithHelper do
      defmacro validate(list, direction \\\\ :asc) do
        quote do
          list = unquote(list)
          direction = unquote(direction)

          case list do
            [] -> :ok
            [_] -> :ok
            _ -> check_order(list, direction, 0)
          end
        end
      end

      @doc false
      def check_order([_], _dir, _idx), do: :ok

      def check_order([_a, _b | _rest], :asc, _idx), do: :asc
      def check_order([_a, _b | _rest], :desc, _idx), do: :desc
    end
    """

    message = "function check_order/3 is unused"
    confirm_fix(fix(input, message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MacroWithHelper do
      defmacro validate(list, direction \\\\ :asc) do
        quote do
          _ = check_order(list, direction, 0)
        end
      end

      defp check_order([_], _dir, _idx), do: :ok
    end
    """

    message = "function check_order/3 is unused"
    assert valid_syntax?(fix(input, message))
  end

  test "returns source unchanged when function is genuinely unused (no quote call)" do
    input = """
    defmodule UnusedHelper do
      defp helper(x), do: x + 1
    end
    """

    message = "function helper/1 is unused"
    confirm_fix(fix(input, message), input)
  end

  test "returns source unchanged when defp line not found" do
    input = """
    defmodule SomeModule do
      def foo, do: :ok
    end
    """

    message = "function bar/1 is unused"
    confirm_fix(fix(input, message), input)
  end

  test "handles single-clause defp" do
    input = """
    defmodule SingleClause do
      defmacro greet(name) do
        quote do
          name = unquote(name)
          build_greeting(name)
        end
      end

      defp build_greeting(name), do: "Hello, " <> name
    end
    """

    expected = """
    defmodule SingleClause do
      defmacro greet(name) do
        quote do
          name = unquote(name)
          build_greeting(name)
        end
      end

      @doc false
      def build_greeting(name), do: "Hello, " <> name
    end
    """

    message = "function build_greeting/1 is unused"
    confirm_fix(fix(input, message), expected)
  end

  test "does not add duplicate @doc false" do
    input = """
    defmodule AlreadyDoc do
      defmacro foo(x) do
        quote do
          bar(unquote(x))
        end
      end

      @doc false
      defp bar(x), do: x
    end
    """

    expected = """
    defmodule AlreadyDoc do
      defmacro foo(x) do
        quote do
          bar(unquote(x))
        end
      end

      @doc false
      def bar(x), do: x
    end
    """

    message = "function bar/1 is unused"
    confirm_fix(fix(input, message), expected)
  end
end
