defmodule Credence.Semantic.FixSpawnMonitorPatternMatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixSpawnMonitorPatternMatch

  # Verbatim compiler output for `{:ok, pid} = spawn_monitor(fn -> :ok end)`.
  @real_message """
  the following pattern will never match:

      {:ok, pid} = spawn_monitor(fn -> :ok end)

  because the right-hand side has type:

      dynamic({pid(), reference()})
  """

  defp fix(source, message, line \\ 1) do
    FixSpawnMonitorPatternMatch.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces {:ok, pid} with {pid, _ref} in spawn_monitor pattern" do
    input = ~S"""
    defmodule SpawnMonitorPattern do
      def run do
        {:ok, pid} = spawn_monitor(fn -> :ok end)
        {pid, :done}
      end
    end
    """

    expected = ~S"""
    defmodule SpawnMonitorPattern do
      def run do
        {pid, _ref} = spawn_monitor(fn -> :ok end)
        {pid, :done}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "rewrites the spawn_monitor/3 form the same way" do
    input = ~S"""
    defmodule SpawnMonitorMfa do
      def run do
        {:ok, pid} = spawn_monitor(Worker, :run, [1])
        pid
      end
    end
    """

    expected = ~S"""
    defmodule SpawnMonitorMfa do
      def run do
        {pid, _ref} = spawn_monitor(Worker, :run, [1])
        pid
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "rewrites every offending occurrence in the file" do
    input = ~S"""
    defmodule TwoSpawns do
      def run do
        {:ok, first} = spawn_monitor(fn -> :a end)
        {:ok, second} = spawn_monitor(fn -> :b end)
        {first, second}
      end
    end
    """

    expected = ~S"""
    defmodule TwoSpawns do
      def run do
        {first, _ref} = spawn_monitor(fn -> :a end)
        {second, _ref} = spawn_monitor(fn -> :b end)
        {first, second}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "picks a non-colliding name when the bound variable is _ref" do
    input = ~S"""
    defmodule RefCollision do
      def run do
        {:ok, _ref} = spawn_monitor(fn -> :ok end)
        :ok
      end
    end
    """

    expected = ~S"""
    defmodule RefCollision do
      def run do
        {_ref, _monitor_ref} = spawn_monitor(fn -> :ok end)
        :ok
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule SpawnMonitorPattern do
      def run do
        {:ok, pid} = spawn_monitor(fn -> :ok end)
        {pid, :done}
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged when no spawn_monitor pattern present" do
    input = ~S"""
    defmodule CleanExample do
      def run do
        {pid, ref} = spawn_monitor(fn -> :ok end)
        {pid, ref}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "leaves a match on a variable named spawn_monitor alone" do
    input = ~S"""
    defmodule VariableRhs do
      def run(spawn_monitor) do
        {:ok, pid} = spawn_monitor
        pid
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "leaves qualified Kernel.spawn_monitor calls alone" do
    input = ~S"""
    defmodule QualifiedCall do
      def run do
        {:ok, pid} = Kernel.spawn_monitor(fn -> :ok end)
        pid
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "returns source unchanged for unrelated code" do
    input = ~S"""
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
