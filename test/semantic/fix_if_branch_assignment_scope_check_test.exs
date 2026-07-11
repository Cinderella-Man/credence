defmodule Credence.Semantic.FixIfBranchAssignmentScopeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixIfBranchAssignmentScope

  @source ~S"""
  defmodule M do
    def check(state) do
      if state.paused do
        new_service = Map.put(state, :timer_ref, nil)
        {:paused, new_service}
      else
        new_service = %{state | status: :active}
        {:active, new_service}
      end

      Map.put(new_service, :checked, true)
    end
  end
  """

  @real_message "undefined variable \"new_service\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {11, 5}, file: path}
    assert FixIfBranchAssignmentScope.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}, file: path}
    refute FixIfBranchAssignmentScope.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {11, 5}, file: path}
    refute FixIfBranchAssignmentScope.match?(diag)
  end

  test "ignores undefined variable not in if branch pattern" do
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
    refute FixIfBranchAssignmentScope.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {11, 5}, file: "unused"}
    assert FixIfBranchAssignmentScope.to_issue(diag).rule == :fix_if_branch_assignment_scope
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}, file: "unused"}
    assert FixIfBranchAssignmentScope.to_issue(diag).meta.line == 42
  end
end
