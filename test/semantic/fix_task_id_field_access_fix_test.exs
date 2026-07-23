defmodule Credence.Semantic.FixTaskIdFieldAccessFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixTaskIdFieldAccess

  @real_message "unknown key .id in expression:\n\n    task.id\n\nthe given type does not have the given key:\n\n    dynamic(%Task{mfa: {atom(), atom(), integer()}, owner: pid(), pid: pid(), ref: term()})\n"

  # The fix locates the access purely by position; the message is along for
  # realism. Every {line, col} used below is the position the real compiler
  # reported for that exact fixture (columns point at the `id` token and are
  # counted in graphemes).
  defp fix(source, position) do
    FixTaskIdFieldAccess.fix(source, %{
      severity: :warning,
      message: @real_message,
      position: position
    })
  end

  test "replaces the flagged task.id with task.ref" do
    input = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.id
      end
    end
    """

    expected = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.ref
      end
    end
    """

    confirm_fix(fix(input, {4, 10}), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.id
      end
    end
    """

    assert valid_syntax?(fix(input, {4, 10}))
  end

  test "leaves a .identity access earlier on the same line untouched" do
    input = """
    defmodule TaskIdField do
      def go(m) do
        task = Task.async(fn -> 1 end)
        {m.identity, task.id}
      end
    end
    """

    expected = """
    defmodule TaskIdField do
      def go(m) do
        task = Task.async(fn -> 1 end)
        {m.identity, task.ref}
      end
    end
    """

    confirm_fix(fix(input, {4, 23}), expected)
  end

  test "fixes only the flagged access when the line has two task.id" do
    input = """
    defmodule TaskIdField do
      def go do
        task = Task.async(fn -> 1 end)
        {task.id, task.id}
      end
    end
    """

    expected = """
    defmodule TaskIdField do
      def go do
        task = Task.async(fn -> 1 end)
        {task.ref, task.id}
      end
    end
    """

    confirm_fix(fix(input, {4, 11}), expected)
  end

  test "fixes a dotted receiver" do
    input = """
    defmodule TaskIdField do
      def go do
        m = %{task: Task.async(fn -> 1 end)}
        m.task.id
      end
    end
    """

    expected = """
    defmodule TaskIdField do
      def go do
        m = %{task: Task.async(fn -> 1 end)}
        m.task.ref
      end
    end
    """

    confirm_fix(fix(input, {4, 12}), expected)
  end

  test "no-op when the column does not point at a .id access" do
    input = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.id
      end
    end
    """

    confirm_fix(fix(input, {4, 5}), input)
  end

  test "no-op when the column points into a longer identifier" do
    input = """
    defmodule TaskIdField do
      def go(m) do
        task = Task.async(fn -> 1 end)
        {m.identity, task.id}
      end
    end
    """

    confirm_fix(fix(input, {4, 8}), input)
  end

  test "no-op when the diagnostic has no column" do
    input = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.id
      end
    end
    """

    confirm_fix(fix(input, 4), input)
  end

  test "no-op when the flagged line does not exist" do
    input = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.id
      end
    end
    """

    confirm_fix(fix(input, {40, 10}), input)
  end
end
