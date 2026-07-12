defmodule Credence.Semantic.NoCondVariableAssignmentInInnerBranchCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoCondVariableAssignmentInInnerBranch

  @source ~S"""
  defmodule Example do
    def count_above(list, threshold) do
      Enum.each(list, fn x ->
        if x > threshold do
          count = 1
        else
          count = 0
        end

        count
      end)
    end
  end
  """

  @real_message "undefined variable \"count\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {10, 9}, file: path}
    assert NoCondVariableAssignmentInInnerBranch.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}, file: path}
    refute NoCondVariableAssignmentInInnerBranch.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {10, 9}, file: path}
    refute NoCondVariableAssignmentInInnerBranch.match?(diag)
  end

  test "ignores generic compile error wrapper", %{source_path: path} do
    diag = %{
      severity: :error,
      message: "cannot compile module Example (errors have been logged)",
      position: 0,
      file: path
    }

    refute NoCondVariableAssignmentInInnerBranch.match?(diag)
  end

  test "ignores undefined variable not in if/else branch assignment pattern" do
    source = ~S"""
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
    refute NoCondVariableAssignmentInInnerBranch.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {10, 9}, file: "unused"}

    assert NoCondVariableAssignmentInInnerBranch.to_issue(diag).rule ==
             :no_cond_variable_assignment_in_inner_branch
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}, file: "unused"}
    assert NoCondVariableAssignmentInInnerBranch.to_issue(diag).meta.line == 42
  end
end
