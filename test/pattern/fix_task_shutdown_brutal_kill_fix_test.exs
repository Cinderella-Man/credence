defmodule Credence.Pattern.FixTaskShutdownBrutalKillFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixTaskShutdownBrutalKill

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

  test "no-op on the piped form (not flagged, so not fixed)" do
    input = "task |> Task.shutdown(:brutal)"
    confirm_fix(fix(FixTaskShutdownBrutalKill, input), input)
  end
end
