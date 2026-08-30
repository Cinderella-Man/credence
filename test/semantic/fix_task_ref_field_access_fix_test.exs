defmodule Credence.Semantic.FixTaskRefFieldAccessFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.FixTaskRefFieldAccess

  @message "Task.ref/1 is undefined or private"

  defp fix(source, position) do
    FixTaskRefFieldAccess.fix(source, %{
      severity: :warning,
      message: @message,
      position: position
    })
  end

  test "rewrites the flagged Task.ref(task) to task.ref" do
    input = """
    defmodule CredenceTaskRefFlagship do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = Task.ref(task)
        {task, ref}
      end
    end
    """

    expected = """
    defmodule CredenceTaskRefFlagship do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = task.ref
        {task, ref}
      end
    end
    """

    confirm_fix(fix(input, {4, 16}), expected)
  end

  test "rewrites a call argument into a field access on the call result" do
    input = """
    defmodule CredenceTaskRefCompound do
      def monitor_first(tasks) do
        Task.ref(hd(tasks))
      end
    end
    """

    expected = """
    defmodule CredenceTaskRefCompound do
      def monitor_first(tasks) do
        hd(tasks).ref
      end
    end
    """

    confirm_fix(fix(input, {3, 10}), expected)
  end

  test "rewrites a struct-field argument into a chained field access" do
    input = """
    defmodule CredenceTaskRefChained do
      def get_ref(state) do
        Task.ref(state.task)
      end
    end
    """

    expected = """
    defmodule CredenceTaskRefChained do
      def get_ref(state) do
        state.task.ref
      end
    end
    """

    confirm_fix(fix(input, {3, 10}), expected)
  end

  test "only the flagged call changes; an identical call on another line survives" do
    input = """
    defmodule CredenceTaskRefTwoCalls do
      def a(t), do: Task.ref(t)
      def b(t), do: Task.ref(t)
    end
    """

    expected = """
    defmodule CredenceTaskRefTwoCalls do
      def a(t), do: t.ref
      def b(t), do: Task.ref(t)
    end
    """

    confirm_fix(fix(input, {2, 22}), expected)
  end

  test "fixes on a line-only position when the line has exactly one candidate" do
    input = """
    defmodule CredenceTaskRefLineOnly do
      def a(t) do
        Task.ref(t)
      end
    end
    """

    expected = """
    defmodule CredenceTaskRefLineOnly do
      def a(t) do
        t.ref
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "returns source unchanged when the column does not anchor on the call" do
    input = """
    defmodule CredenceTaskRefBadCol do
      def a(t) do
        Task.ref(t)
      end
    end
    """

    confirm_fix(fix(input, {3, 1}), input)
  end

  test "returns source unchanged when the flagged line does not exist" do
    input = """
    defmodule CredenceTaskRefBadLine do
      def a(t) do
        Task.ref(t)
      end
    end
    """

    confirm_fix(fix(input, {99, 10}), input)
  end

  test "returns source unchanged for the capture form (&Task.ref/1 admits no field access)" do
    input = """
    defmodule CredenceTaskRefCaptureUnit do
      def a, do: &Task.ref/1
    end
    """

    confirm_fix(fix(input, {2, 20}), input)
  end

  test "returns source unchanged for the piped form" do
    input = """
    defmodule CredenceTaskRefPipeUnit do
      def a(t), do: t |> Task.ref()
    end
    """

    confirm_fix(fix(input, {2, 27}), input)
  end

  test "returns source unchanged for the Elixir.-prefixed spelling" do
    input = """
    defmodule CredenceTaskRefElixirPrefixUnit do
      def a(t), do: Elixir.Task.ref(t)
    end
    """

    confirm_fix(fix(input, {2, 29}), input)
  end

  test "returns source unchanged when no Task.ref present" do
    input = """
    defmodule CredenceTaskRefClean do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, {2, 1}), input)
  end

  test "fixed flagship output is well-formed (parses)" do
    input = """
    defmodule CredenceTaskRefParses do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = Task.ref(task)
        {task, ref}
      end
    end
    """

    assert valid_syntax?(fix(input, {4, 16}))
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceTaskRefCompiles do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = Task.ref(task)
        {task, ref}
      end
    end
    """

    assert compiles?(fix(input, {4, 16}))
  end

  test "end-to-end: the semantic phase fixes the flagship input and touches nothing else" do
    input = """
    defmodule CredenceTaskRefE2E do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = Task.ref(task)
        {task, ref}
      end
    end
    """

    expected = """
    defmodule CredenceTaskRefE2E do
      def get_ref do
        task = Task.async(fn -> 42 end)
        ref = task.ref
        {task, ref}
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: two flagged calls on one line are both fixed via their own columns" do
    input = """
    defmodule CredenceTaskRefTwoOnLineE2E do
      def a(t1, t2), do: {Task.ref(t1), Task.ref(t2)}
    end
    """

    expected = """
    defmodule CredenceTaskRefTwoOnLineE2E do
      def a(t1, t2), do: {t1.ref, t2.ref}
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a Task.ref spelling that resolves elsewhere via alias is left untouched" do
    input = """
    defmodule CredenceTaskRefAliasShadowE2E do
      def a(t), do: Task.ref(t)

      def b(t) do
        alias CredenceTaskRefAliasShadowE2E.Tasks, as: Task
        Task.ref(t)
      end
    end
    """

    expected = """
    defmodule CredenceTaskRefAliasShadowE2E do
      def a(t), do: t.ref

      def b(t) do
        alias CredenceTaskRefAliasShadowE2E.Tasks, as: Task
        Task.ref(t)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the multi-line call form" do
    input = """
    defmodule CredenceTaskRefMultilineE2E do
      def a(t) do
        Task.ref(
          t
        )
      end
    end
    """

    expected = """
    defmodule CredenceTaskRefMultilineE2E do
      def a(t) do
        t.ref
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the capture form is deliberately left unfixed" do
    input = """
    defmodule CredenceTaskRefCaptureE2E do
      def a, do: &Task.ref/1
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end

  test "end-to-end: the piped form is deliberately left unfixed" do
    input = """
    defmodule CredenceTaskRefPipeE2E do
      def a(t), do: t |> Task.ref()
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end
end
