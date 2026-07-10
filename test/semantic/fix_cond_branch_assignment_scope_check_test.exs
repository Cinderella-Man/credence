defmodule Credence.Semantic.FixCondBranchAssignmentScopeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixCondBranchAssignmentScope

  @source ~S"""
  defmodule M do
    def calc(values) do
      wma1_val =
        cond do
          true ->
            Enum.sum(values)
          false ->
            0
        end

      wma1_val * 2
    end
  end
  """

  @real_message "undefined variable \"wma1_val\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {11, 5}, file: path}
    assert FixCondBranchAssignmentScope.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}, file: path}
    refute FixCondBranchAssignmentScope.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {11, 5}, file: path}
    refute FixCondBranchAssignmentScope.match?(diag)
  end

  test "ignores generic compile error wrapper", %{source_path: path} do
    diag = %{
      severity: :error,
      message: "cannot compile module M (errors have been logged)",
      position: 0,
      file: path
    }

    refute FixCondBranchAssignmentScope.match?(diag)
  end

  test "ignores undefined variable not in cond/case/if pattern" do
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
    refute FixCondBranchAssignmentScope.match?(diag)
    File.rm(path)
  end

  test "matches diagnostic for case pattern", %{source_path: _path} do
    source = ~S"""
    defmodule M do
      def calc(x) do
        result =
          case x do
            :a -> 1
            :b -> 2
          end

        result + 10
      end
    end
    """

    path =
      Path.join(System.tmp_dir!(), "credence_case_#{System.unique_integer([:positive])}.ex")

    File.write!(path, source)
    diag = %{severity: :error, message: "undefined variable \"result\"", position: {9, 5}, file: path}
    assert FixCondBranchAssignmentScope.match?(diag)
    File.rm(path)
  end

  test "matches diagnostic for if pattern", %{source_path: _path} do
    source = ~S"""
    defmodule M do
      def calc(x) do
        val =
          if x > 0 do
            x * 2
          else
            0
          end

        val + 1
      end
    end
    """

    path =
      Path.join(System.tmp_dir!(), "credence_if_#{System.unique_integer([:positive])}.ex")

    File.write!(path, source)
    diag = %{severity: :error, message: "undefined variable \"val\"", position: {11, 5}, file: path}
    assert FixCondBranchAssignmentScope.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {11, 5}, file: "unused"}
    assert FixCondBranchAssignmentScope.to_issue(diag).rule == :fix_cond_branch_assignment_scope
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}, file: "unused"}
    assert FixCondBranchAssignmentScope.to_issue(diag).meta.line == 42
  end
end
