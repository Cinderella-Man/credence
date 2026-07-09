defmodule Credence.Semantic.NoFunctionInModuleAttributeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoFunctionInModuleAttribute

  @match_msg "cannot inject attribute @default into function/macro because cannot escape #Function<0.118257976 in file:credence_check.ex>"

  defp fix(source, message \\ @match_msg, line \\ 1) do
    NoFunctionInModuleAttribute.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "inlines fn from attribute into call site and removes attribute" do
    input = """
    defmodule FuncAttr do
      @default fn -> System.monotonic_time(:millisecond) end

      def now, do: @default.()
    end
    """

    expected = """
    defmodule FuncAttr do
      def now do
        (fn -> System.monotonic_time(:millisecond) end).()
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "inlines fn with arguments" do
    input = """
    defmodule FuncAttr do
      @adder fn a, b -> a + b end

      def add(a, b), do: @adder.(a, b)
    end
    """

    expected = """
    defmodule FuncAttr do
      def add(a, b) do
        (fn a, b -> a + b end).(a, b)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "inlines multiple fn attributes" do
    input = """
    defmodule FuncAttr do
      @default fn -> System.monotonic_time(:millisecond) end
      @adder fn a, b -> a + b end

      def now, do: @default.()
      def add(a, b), do: @adder.(a, b)
    end
    """

    expected = """
    defmodule FuncAttr do
      def now do
        (fn -> System.monotonic_time(:millisecond) end).()
      end

      def add(a, b) do
        (fn a, b -> a + b end).(a, b)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule FuncAttr do
      @default fn -> System.monotonic_time(:millisecond) end

      def now, do: @default.()
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no fn attributes" do
    source = """
    defmodule M do
      @x 42
      def f, do: @x
    end
    """

    confirm_fix(fix(source), source)
  end
end
