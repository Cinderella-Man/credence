defmodule Credence.Semantic.FixUndefinedVariableInEqualityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUndefinedVariableInEquality

  @source """
  defmodule FileUpload.Router do
    defp handle_dispatch(conn) do
      cond do
        conn.path_info == ["api", "uploads", id] ->
          id
        true ->
          :ok
      end
    end
  end
  """

  @real_message "undefined variable \"id\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic when source has list equality pattern", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {4, 72}, file: path}
    assert FixUndefinedVariableInEquality.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "undefined function foo/1", position: {1, 1}, file: path}
    refute FixUndefinedVariableInEquality.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {4, 72}, file: path}
    refute FixUndefinedVariableInEquality.match?(diag)
  end

  test "ignores undefined variable not in list equality pattern" do
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
    refute FixUndefinedVariableInEquality.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {4, 72}, file: "unused"}

    assert FixUndefinedVariableInEquality.to_issue(diag).rule ==
             :fix_undefined_variable_in_equality
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {10, 72}, file: "unused"}
    assert FixUndefinedVariableInEquality.to_issue(diag).meta.line == 10
  end

  test "ignores generic compile error wrapper", %{source_path: path} do
    diag = %{
      severity: :error,
      message:
        "credence_check.ex: cannot compile module FileUpload.Router (errors have been logged)",
      position: 0,
      file: path
    }

    refute FixUndefinedVariableInEquality.match?(diag)
  end
end
