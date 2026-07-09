defmodule Credence.Semantic.FixInvalidCaptureWithArgumentsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixInvalidCaptureWithArguments

  @real_message "undefined variable \"func\""

  defp fix(source, message, line \\ 1) do
    FixInvalidCaptureWithArguments.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes &Mod.fun(args)/N to fn -> Mod.fun(args) end" do
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

    confirm_fix(fix(input, @real_message, 3), expected)
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

    assert valid_syntax?(fix(input, @real_message, 3))
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

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "leaves valid capture &Mod.fun(&1, &2) unchanged" do
    input = """
    defmodule Example do
      def start do
        add = &Kernel.+/2
        add.(1, 2)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "returns source unchanged when no capture pattern present" do
    input = """
    defmodule Example do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
