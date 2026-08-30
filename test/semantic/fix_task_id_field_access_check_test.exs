defmodule Credence.Semantic.FixTaskIdFieldAccessCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixTaskIdFieldAccess

  # Real compiler output (Elixir 1.20) for `task.id` where `task` is a %Task{}.
  @task_message """
  unknown key .id in expression:

      task.id

  the given type does not have the given key:

      dynamic(%Task{mfa: {atom(), atom(), integer()}, owner: pid(), pid: pid(), ref: term()})

  where "task" was given the type:

      # type: dynamic(%Task{mfa: {atom(), atom(), integer()}, owner: pid(), pid: pid()})
      # from: probe.ex:3:10
      task = Task.async(fn -> 1 end)
  """

  # Real compiler output for `r.id` where `r` is a %URI{} — same "unknown key
  # .id" wording, but `.ref` would fix nothing here.
  @uri_message """
  unknown key .id in expression:

      r.id

  the given type does not have the given key:

      dynamic(%URI{
        scheme: term(),
        authority: nil or binary(),
        userinfo: term(),
        host: term(),
        port: term(),
        path: term(),
        query: nil or binary(),
        fragment: term()
      })

  where "r" was given the type:

      # type: dynamic(%URI{authority: nil or binary(), query: nil or binary()})
      # from: probe.ex:3:7
      r = URI.parse("http://x")
  """

  # Real compiler output for `m.id` where `m` is a plain map that merely
  # contains a %Task{} — the flagged type is the map, not the Task.
  @map_with_task_message """
  unknown key .id in expression:

      m.id

  the given type does not have the given key:

      dynamic(%{task: %Task{mfa: {atom(), atom(), integer()}, owner: pid(), pid: pid(), ref: term()}})

  where "m" was given the type:

      # type: dynamic(%{task: %Task{mfa: {atom(), atom(), integer()}, owner: pid(), pid: pid()}})
      # from: probe.ex:3:7
      m = %{task: Task.async(fn -> 1 end)}
  """

  test "matches the Task .id warning" do
    diag = %{severity: :warning, message: @task_message, position: {4, 10}}
    assert FixTaskIdFieldAccess.match?(diag)
  end

  test "ignores the same warning on a non-Task struct" do
    diag = %{severity: :warning, message: @uri_message, position: {4, 7}}
    refute FixTaskIdFieldAccess.match?(diag)
  end

  test "ignores a flagged type that merely contains a Task" do
    diag = %{severity: :warning, message: @map_with_task_message, position: {4, 7}}
    refute FixTaskIdFieldAccess.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixTaskIdFieldAccess.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :warning,
      message: "credence_check.ex: cannot compile module (errors have been logged)",
      position: 0
    }

    refute FixTaskIdFieldAccess.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @task_message, position: {4, 10}}
    refute FixTaskIdFieldAccess.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @task_message, position: {62, 55}}
    assert FixTaskIdFieldAccess.to_issue(diag).rule == :fix_task_id_field_access
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @task_message, position: {42, 5}}
    assert FixTaskIdFieldAccess.to_issue(diag).meta.line == 42
  end
end
