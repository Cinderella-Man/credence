defmodule Credence.Semantic.FixInvalidCaptureWithArgumentsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixInvalidCaptureWithArguments

  # Real message shape from Code.with_diagnostics (abbreviated body; the rule
  # matches on the "invalid args for &" prefix).
  @real_message "invalid args for &, expected one of:\n\n  * &Mod.fun/arity ..."

  defp fix(source, line \\ 1) do
    FixInvalidCaptureWithArguments.fix(source, %{
      severity: :error,
      message: @real_message,
      position: {line, 1}
    })
  end

  test "fixes remote &Mod.fun(args)/0 to fn -> Mod.fun(args) end" do
    input = """
    defmodule Example do
      def start do
        clock = &System.monotonic_time(:millisecond)/0
        clock.()
      end
    end
    """

    expected = """
    defmodule Example do
      def start do
        clock = fn -> System.monotonic_time(:millisecond) end
        clock.()
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes local &fun(args)/0 to fn -> fun(args) end" do
    input = """
    defmodule Example do
      def greet(name) do
        thunk = &build_greeting(name)/0
        thunk.()
      end

      defp build_greeting(name), do: "hi " <> name
    end
    """

    expected = """
    defmodule Example do
      def greet(name) do
        thunk = fn -> build_greeting(name) end
        thunk.()
      end

      defp build_greeting(name), do: "hi " <> name
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes only the invalid capture, leaving a valid division capture alone" do
    input = """
    defmodule Example do
      def start(list) do
        clock = &System.monotonic_time(:millisecond)/0
        halves = Enum.map(list, &(&1 / 2))
        {clock.(), halves}
      end
    end
    """

    expected = """
    defmodule Example do
      def start(list) do
        clock = fn -> System.monotonic_time(:millisecond) end
        halves = Enum.map(list, &(&1 / 2))
        {clock.(), halves}
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes an invalid capture without rewriting quoted capture data" do
    input = """
    defmodule InvalidCaptureQuoteDataFixture do
      def real, do: &System.monotonic_time(:millisecond)/0
      def quoted, do: quote(do: &foo(:x)/0)
    end
    """

    expected = """
    defmodule InvalidCaptureQuoteDataFixture do
      def real, do: fn -> System.monotonic_time(:millisecond) end
      def quoted, do: quote(do: &foo(:x)/0)
    end
    """

    confirm_fix(fix(input, 2), expected)
  end

  test "compiler diagnostic selects and repairs the rule through Semantic dispatch" do
    input = """
    defmodule InvalidCaptureDispatchFixture do
      def start do
        clock = &System.monotonic_time(:millisecond)/0
        clock.()
      end
    end
    """

    expected = """
    defmodule InvalidCaptureDispatchFixture do
      def start do
        clock = fn -> System.monotonic_time(:millisecond) end
        clock.()
      end
    end
    """

    assert {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)
    assert Enum.any?(diagnostics, &FixInvalidCaptureWithArguments.match?/1)
    confirm_fix(Credence.Semantic.fix(input), expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def start do
        clock = &System.monotonic_time(:millisecond)/0
        clock.()
      end
    end
    """

    assert valid_syntax?(fix(input, 3))
  end

  test "leaves &fun(args)/N with N > 0 unchanged (arity intent unknowable)" do
    input = """
    defmodule Example do
      def go(list, x) do
        Enum.map(list, &transform(x)/1)
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves a valid capture of a division &(&1 / 2) unchanged" do
    input = """
    defmodule Example do
      def halve(list) do
        Enum.map(list, &(&1 / 2))
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves a valid capture with a /N-looking body &div(&1, 2)/2 unchanged" do
    input = """
    defmodule Example do
      def halve(list) do
        Enum.map(list, &div(&1, 2)/2)
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves valid capture &Mod.fun/arity unchanged" do
    input = """
    defmodule Example do
      def start do
        clock = &System.monotonic_time/1
        clock.(:millisecond)
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves valid capture with capture args &Mod.fun(&1, ...) unchanged" do
    input = """
    defmodule Example do
      def pad(list) do
        Enum.map(list, &String.pad_leading(&1, 5))
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves zero-argument call &Mod.fun()/0 unchanged (not the target shape)" do
    input = """
    defmodule Example do
      def start do
        clock = &System.monotonic_time()/0
        clock.()
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves an operator body &(x * 2 / 0) unchanged" do
    input = """
    defmodule Example do
      def go(x) do
        f = &(x * 2 / 0)
        f
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "returns source unchanged when no capture pattern present" do
    input = """
    defmodule Example do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end
end
