defmodule Credence.Semantic.FixFunctionInModuleAttributeInlineUsagesFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixFunctionInModuleAttributeInlineUsages

  @match_msg "cannot inject attribute @default_clock into function/macro because cannot escape #Function<0.118257976 in file:credence_check.ex>"

  defp fix(source, message \\ @match_msg, line \\ 1) do
    FixFunctionInModuleAttributeInlineUsages.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces @attr fn definition with defp and @attr refs with captures" do
    input = """
    defmodule M do
      @default_clock fn -> System.monotonic_time(:millisecond) end

      def start_link(opts) do
        clock = Keyword.get(opts, :clock, @default_clock)
        {:ok, %{clock: clock}}
      end
    end
    """

    expected = """
    defmodule M do
      defp default_clock, do: System.monotonic_time(:millisecond)

      def start_link(opts) do
        clock = Keyword.get(opts, :clock, &default_clock/0)
        {:ok, %{clock: clock}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "handles fn with arguments" do
    input = """
    defmodule M do
      @adder fn a, b -> a + b end

      def add(x, y), do: Keyword.get([], :add_fn, @adder).(x, y)
    end
    """

    expected = """
    defmodule M do
      defp adder(a, b),
        do: a + b

      def add(x, y) do
        Keyword.get([], :add_fn, &adder/2).(x, y)
      end
    end
    """

    confirm_fix(fix(input), expected)
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

  test "returns source unchanged when only @attr.() calls exist (no value refs)" do
    source = """
    defmodule FuncAttr do
      @default fn -> System.monotonic_time(:millisecond) end

      def now, do: @default.()
    end
    """

    confirm_fix(fix(source), source)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      @default_clock fn -> System.monotonic_time(:millisecond) end

      def start_link(opts) do
        clock = Keyword.get(opts, :clock, @default_clock)
        {:ok, %{clock: clock}}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
