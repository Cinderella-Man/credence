defmodule Credence.Semantic.NoProcessSendTwoArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoProcessSendTwoArgs

  @real_message "expected a map or struct when accessing .normal in expression:\n\n    new_queue.normal\n\nwhere \"new_queue\" was given the type:\n\n    # type: empty_list()\n    # from: credence_check.ex:143:7\n    {nil, new_queue, state}\n\nhint: \"var.field\" (without parentheses) means \"var\" is a map() while \"var.fun()\" (with parentheses) means \"var\" is an atom()\n"

  defp fix(source, message, line \\ 1) do
    NoProcessSendTwoArgs.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces Process.send/2 with Kernel.send/2" do
    input = """
    defmodule ProcessSendTwoArgs do
      def notify(pid, msg) do
        Process.send(pid, msg)
      end
    end
    """

    expected = """
    defmodule ProcessSendTwoArgs do
      def notify(pid, msg) do
        send(pid, msg)
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ProcessSendTwoArgs do
      def notify(pid, msg) do
        Process.send(pid, msg)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no Process.send/2" do
    input = """
    defmodule CleanExample do
      def notify(pid, msg) do
        send(pid, msg)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "does not touch Process.send/3" do
    input = """
    defmodule WithOpts do
      def notify(pid, msg) do
        Process.send(pid, msg, [:nosuspend])
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
