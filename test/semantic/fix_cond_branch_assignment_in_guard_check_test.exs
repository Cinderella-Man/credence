defmodule Credence.Semantic.FixCondBranchAssignmentInGuardCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixCondBranchAssignmentInGuard

  @source ~S"""
  defmodule CondGuardAssignment do
    def check(code, user_id, usages) do
      cond do
        code.max_uses_per_user && user_id ->
          user_key = {code.code, user_id}
          Map.get(usages, user_key, 0) >= code.max_uses_per_user ->
            :exceeded

        true ->
          :ok
      end
    end
  end
  """

  @real_message "undefined variable \"user_key\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_guard_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {6, 35}, file: path}
    assert FixCondBranchAssignmentInGuard.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}, file: path}
    refute FixCondBranchAssignmentInGuard.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {6, 35}, file: path}
    refute FixCondBranchAssignmentInGuard.match?(diag)
  end

  test "ignores undefined variable not in cond guard assignment pattern" do
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
    refute FixCondBranchAssignmentInGuard.match?(diag)
    File.rm(path)
  end

  test "ignores undefined variable that is assigned in branch body but used after cond" do
    source = ~S"""
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

    path =
      Path.join(System.tmp_dir!(), "credence_scope_#{System.unique_integer([:positive])}.ex")

    File.write!(path, source)
    diag = %{severity: :error, message: "undefined variable \"wma1_val\"", position: {11, 5}, file: path}
    refute FixCondBranchAssignmentInGuard.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {6, 35}, file: "unused"}
    assert FixCondBranchAssignmentInGuard.to_issue(diag).rule == :fix_cond_branch_assignment_in_guard
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}, file: "unused"}
    assert FixCondBranchAssignmentInGuard.to_issue(diag).meta.line == 42
  end
end
