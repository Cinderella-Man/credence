defmodule Credence.Semantic.NoIfAssignmentAsStatementCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoIfAssignmentAsStatement

  @source """
  defmodule Mod do
    def example(list) do
      Enum.reduce(list, 0, fn item, acc ->
        if item > 0 do
          cost = 1
        else
          cost = 2
        end

        acc + cost
      end)
    end
  end
  """

  @real_message "undefined variable \"cost\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {10, 13}, file: path}
    assert NoIfAssignmentAsStatement.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}, file: path}
    refute NoIfAssignmentAsStatement.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {10, 13}, file: path}
    refute NoIfAssignmentAsStatement.match?(diag)
  end

  test "ignores generic compile error wrapper", %{source_path: path} do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Mod (errors have been logged)",
      position: 0,
      file: path
    }

    refute NoIfAssignmentAsStatement.match?(diag)
  end

  test "ignores undefined variable not in if/else pattern" do
    source = """
    defmodule Example do
      def test do
        IO.puts(x)
      end
    end
    """

    path =
      Path.join(System.tmp_dir!(), "credence_no_match_#{System.unique_integer([:positive])}.ex")

    File.write!(path, source)
    diag = %{severity: :error, message: "undefined variable \"x\"", position: {3, 13}, file: path}
    refute NoIfAssignmentAsStatement.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {10, 13}, file: "unused"}
    assert NoIfAssignmentAsStatement.to_issue(diag).rule == :no_if_assignment_as_statement
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}, file: "unused"}
    assert NoIfAssignmentAsStatement.to_issue(diag).meta.line == 42
  end
end
