defmodule Credence.Semantic.FixCaseBranchAssignmentScopeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixCaseBranchAssignmentScope

  @source ~S"""
  defmodule M do
    def classify(x) do
      case x do
        :ok -> label = "success"
        :error -> label = "failure"
        _ -> label = "unknown"
      end

      String.upcase(label)
    end
  end
  """

  @real_message "undefined variable \"label\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {9, 17}, file: path}
    assert FixCaseBranchAssignmentScope.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}, file: path}
    refute FixCaseBranchAssignmentScope.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {9, 17}, file: path}
    refute FixCaseBranchAssignmentScope.match?(diag)
  end

  test "ignores undefined variable not in case branch pattern" do
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
    refute FixCaseBranchAssignmentScope.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {9, 17}, file: "unused"}
    assert FixCaseBranchAssignmentScope.to_issue(diag).rule == :fix_case_branch_assignment_scope
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}, file: "unused"}
    assert FixCaseBranchAssignmentScope.to_issue(diag).meta.line == 42
  end
end
