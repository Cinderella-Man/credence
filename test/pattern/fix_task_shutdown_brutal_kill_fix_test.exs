defmodule Credence.Pattern.FixTaskShutdownBrutalKillFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixTaskShutdownBrutalKill
  alias Credence.RuleHelpers

  test "rewrites :brutal to :brutal_kill" do
    input = "Task.shutdown(task, :brutal)"
    expected = "Task.shutdown(task, :brutal_kill)"
    confirm_fix(fix(FixTaskShutdownBrutalKill, input), expected)
  end

  test "rewrites every occurrence in module context without touching anything else" do
    input = """
    defmodule M do
      def stop(task) do
        Task.shutdown(task, :brutal)
      end

      def stop_all(tasks) do
        Enum.each(tasks, fn t -> Task.shutdown(t, :brutal) end)
      end

      def graceful(task), do: Task.shutdown(task, 5000)
    end
    """

    expected = """
    defmodule M do
      def stop(task) do
        Task.shutdown(task, :brutal_kill)
      end

      def stop_all(tasks) do
        Enum.each(tasks, fn t -> Task.shutdown(t, :brutal_kill) end)
      end

      def graceful(task), do: Task.shutdown(task, 5000)
    end
    """

    confirm_fix(fix(FixTaskShutdownBrutalKill, input), expected)
  end

  test "no-op on already-correct :brutal_kill" do
    input = "Task.shutdown(task, :brutal_kill)"
    confirm_fix(fix(FixTaskShutdownBrutalKill, input), input)
  end

  test "rewrites the piped form and emits the same compilable meaning as the control" do
    input = "fn task -> task |> Task.shutdown(:brutal) end"
    expected = "fn task -> task |> Task.shutdown(:brutal_kill) end"
    emitted = fix(FixTaskShutdownBrutalKill, input)

    confirm_fix(emitted, expected)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
  end

  test "rewrites the fully qualified form" do
    input = "Elixir.Task.shutdown(task, :brutal)"
    expected = "Elixir.Task.shutdown(task, :brutal_kill)"
    confirm_fix(fix(FixTaskShutdownBrutalKill, input), expected)
  end

  test "does not rewrite a custom module aliased as Task" do
    input = """
    alias MyApp.Task, as: Task
    Task.shutdown(task, :brutal)
    """

    confirm_fix(fix(FixTaskShutdownBrutalKill, input), input)
  end
end
