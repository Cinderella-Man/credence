defmodule Credence.Semantic.FixUndefinedVariableInHelperScopeCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUndefinedVariableInHelperScope

  @source ~S"""
  defmodule TreeStream do
    use GenServer

    @impl true
    def init(opts) do
      state = %{nodes: %{}, order: [], strategy: :discard}
      {:ok, state}
    end

    @impl true
    def handle_call(:forest, _from, state) do
      result = build_node_tree(state.nodes, :root)
      {:reply, result, state}
    end

    @impl true
    def handle_call(_msg, _from, state) do
      {:reply, :ok, state}
    end

    defp build_node_tree(nodes, id) do
      node = Map.fetch!(nodes, id)
      ordered_children = Enum.filter(state.order, fn c -> c.parent_id == id end)
      Map.put(node, :children, ordered_children)
    end
  end
  """

  @real_message "undefined variable \"state\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic when defp uses caller-scope variable field", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {21, 5}, file: path}
    assert FixUndefinedVariableInHelperScope.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated error", position: {1, 1}, file: path}
    refute FixUndefinedVariableInHelperScope.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {21, 5}, file: path}
    refute FixUndefinedVariableInHelperScope.match?(diag)
  end

  test "ignores undefined variable not in defp helper scope pattern" do
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
    refute FixUndefinedVariableInHelperScope.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {21, 5}, file: "unused"}

    assert FixUndefinedVariableInHelperScope.to_issue(diag).rule ==
             :fix_undefined_variable_in_helper_scope
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {42, 5}, file: "unused"}
    assert FixUndefinedVariableInHelperScope.to_issue(diag).meta.line == 42
  end
end
