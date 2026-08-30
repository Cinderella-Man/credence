defmodule Credence.Semantic.FixTaskAsyncStreamCaseMatchCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixTaskAsyncStreamCaseMatch

  # Real messages captured from `Code.with_diagnostics` compiling the
  # anti-pattern on this Elixir (positions are bare integers there).
  @ok_message """
  the following clause will never match:

      {:ok, results} ->

  because it attempts to match on the result of:

      Task.async_stream(elements, fun, max_concurrency: 4)

  which has type:

      dynamic(({:cont or :halt or :suspend, term()}, term() -> term()))
  """
  @error_message """
  the following clause will never match:

      {:error, reason} ->

  because it attempts to match on the result of:

      Task.async_stream(elements, fun, max_concurrency: 4)

  which has type:

      dynamic(({:cont or :halt or :suspend, term()}, term() -> term()))
  """

  test "matches the diagnostic for the dead {:ok, results} clause" do
    diag = %{severity: :warning, message: @ok_message, position: 4}
    assert FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "matches the diagnostic for the dead {:error, reason} clause" do
    diag = %{severity: :warning, message: @error_message, position: 6}
    assert FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "compiler diagnostics reach this rule through the Semantic pipeline" do
    source = """
    defmodule TaskAsyncStreamCaseMatchCheckPipelineFixture do
      def run(elements, fun) do
        case Task.async_stream(elements, fun, max_concurrency: 4) do
          {:ok, results} -> results
          {:error, reason} -> reason
        end
      end
    end
    """

    issues = Credence.Semantic.analyze(source)

    assert Enum.map(issues, & &1.rule) == [
             :fix_task_async_stream_case_match,
             :fix_task_async_stream_case_match
           ]
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: 1}
    refute FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @ok_message, position: 1}
    refute FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "ignores a case on some other module's async_stream" do
    msg = String.replace(@ok_message, "Task.async_stream(", "MyTask.async_stream(")
    diag = %{severity: :warning, message: msg, position: 4}
    refute FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "ignores a subject whose type is not a function (shadowed Task returning tuples)" do
    msg = """
    the following clause will never match:

        {:error, reason} ->

    because it attempts to match on the result of:

        Task.async_stream(elements, fun)

    which has type:

        dynamic({:ok, list(term())})
    """

    diag = %{severity: :warning, message: msg, position: 6}
    refute FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "ignores a dead clause that is not a tagged tuple" do
    msg = """
    the following clause will never match:

        [head | tail] ->

    because it attempts to match on the result of:

        Task.async_stream(elements, fun)

    which has type:

        dynamic(({:cont or :halt or :suspend, term()}, term() -> term()))
    """

    diag = %{severity: :warning, message: msg, position: 4}
    refute FixTaskAsyncStreamCaseMatch.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @ok_message, position: 4}
    assert FixTaskAsyncStreamCaseMatch.to_issue(diag).rule == :fix_task_async_stream_case_match
  end

  test "sets the line in issue meta from an integer position" do
    diag = %{severity: :warning, message: @ok_message, position: 42}
    assert FixTaskAsyncStreamCaseMatch.to_issue(diag).meta.line == 42
  end

  test "sets the line in issue meta from a {line, col} position" do
    diag = %{severity: :warning, message: @ok_message, position: {42, 5}}
    assert FixTaskAsyncStreamCaseMatch.to_issue(diag).meta.line == 42
  end
end
