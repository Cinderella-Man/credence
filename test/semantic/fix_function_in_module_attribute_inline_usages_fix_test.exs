defmodule Credence.Semantic.FixFunctionInModuleAttributeInlineUsagesFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

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

      def add(x, y), do: Keyword.get([], :add_fn, &adder/2).(x, y)
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "rewrites direct @attr.() calls to plain local calls" do
    input = """
    defmodule FuncAttr do
      @default fn -> System.monotonic_time(:millisecond) end

      def now, do: @default.()
    end
    """

    expected = """
    defmodule FuncAttr do
      defp default, do: System.monotonic_time(:millisecond)
      def now, do: default()
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "rewrites a mix of value references and direct calls" do
    input = """
    defmodule M do
      @fmt fn x -> to_string(x) end

      def all(list), do: Enum.map(list, @fmt)
      def one(x), do: @fmt.(x)
    end
    """

    expected = """
    defmodule M do
      defp fmt(x),
        do: to_string(x)

      def all(list), do: Enum.map(list, &fmt/1)
      def one(x), do: fmt(x)
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "handles a multi-statement fn body" do
    input = """
    defmodule M do
      @log fn msg ->
        IO.puts(msg)
        msg
      end

      def run(msgs), do: Enum.map(msgs, @log)
    end
    """

    expected = """
    defmodule M do
      defp log(msg) do
        IO.puts(msg)
        msg
      end

      def run(msgs), do: Enum.map(msgs, &log/1)
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

  test "leaves a multi-clause fn attribute unchanged (deliberately skipped)" do
    source = """
    defmodule M do
      @handler fn
        :ok -> 1
        _ -> 0
      end

      def run(list), do: Enum.map(list, @handler)
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves a guarded fn attribute unchanged (deliberately skipped)" do
    source = """
    defmodule M do
      @check fn x when is_integer(x) -> x end

      def run(list), do: Enum.map(list, @check)
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves a reassigned fn attribute unchanged (deliberately skipped)" do
    source = """
    defmodule M do
      @clock fn -> 1 end
      def a, do: @clock
      @clock fn -> 2 end
      def b, do: @clock
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves an attribute with a module-level value reference unchanged (deliberately skipped)" do
    source = """
    defmodule M do
      @a fn -> 1 end
      @b @a

      def g, do: @a
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves an attribute with a module-level compile-time call unchanged (deliberately skipped)" do
    source = """
    defmodule M do
      @a fn -> 41 end
      @b @a.() + 1

      def g, do: @a
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves an arity-mismatched direct call unchanged (deliberately skipped)" do
    source = """
    defmodule M do
      @one fn x -> x end

      def g, do: @one.(1, 2)
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves an attribute whose name collides with a Kernel auto-import unchanged (deliberately skipped)" do
    source = """
    defmodule M do
      @node fn -> :local end

      def g, do: @node.()
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves a file with two modules unchanged (deliberately skipped)" do
    source = """
    defmodule A do
      @a fn -> 1 end
      def g, do: @a
    end

    defmodule B do
      def h, do: 2
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves an attribute referenced inside a quote block unchanged (deliberately skipped)" do
    source = """
    defmodule M do
      @a fn -> 1 end

      def g, do: @a

      defmacro m do
        quote do
          @a
        end
      end
    end
    """

    confirm_fix(fix(source), source)
  end

  test "rewrites a reference in a def default argument, and the result compiles" do
    input = """
    defmodule CredenceFnAttrDefaultArg do
      @clock fn -> System.monotonic_time(:millisecond) end

      def f(g \\\\ @clock), do: g.()
    end
    """

    expected = """
    defmodule CredenceFnAttrDefaultArg do
      defp clock, do: System.monotonic_time(:millisecond)
      def f(g \\\\ &clock/0), do: g.()
    end
    """

    confirm_fix(fix(input), expected)
    assert compiles?(fix(input))
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceFnAttrCompiles do
      @default_clock fn -> System.monotonic_time(:millisecond) end

      def start_link(opts) do
        clock = Keyword.get(opts, :clock, @default_clock)
        {:ok, %{clock: clock}}
      end
    end
    """

    assert compiles?(fix(input))
  end

  test "fixed direct-call output compiles" do
    input = """
    defmodule CredenceFnAttrCallCompiles do
      @default fn -> System.monotonic_time(:millisecond) end

      def now, do: @default.()
    end
    """

    assert compiles?(fix(input))
  end

  test "end-to-end: the semantic phase dispatches this rule on the real diagnostic" do
    input = """
    defmodule CredenceFnAttrE2E do
      @default_clock fn -> System.monotonic_time(:millisecond) end

      def start_link(opts) do
        clock = Keyword.get(opts, :clock, @default_clock)
        {:ok, %{clock: clock}}
      end
    end
    """

    expected = """
    defmodule CredenceFnAttrE2E do
      defp default_clock, do: System.monotonic_time(:millisecond)

      def start_link(opts) do
        clock = Keyword.get(opts, :clock, &default_clock/0)
        {:ok, %{clock: clock}}
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
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
