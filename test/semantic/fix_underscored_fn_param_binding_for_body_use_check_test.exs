defmodule Credence.Semantic.FixUnderscoredFnParamBindingForBodyUseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUnderscoredFnParamBindingForBodyUse

  @source """
  defmodule M do
    defp resolve_field(_field, ov, _bv, _tv) when ov == _bv do
      {:ok, tv}
    end
  end
  """

  @real_message "undefined variable \"tv\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic when source has underscored param", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {3, 11}, file: path}
    assert FixUnderscoredFnParamBindingForBodyUse.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}, file: path}
    refute FixUnderscoredFnParamBindingForBodyUse.match?(diag)
  end

  test "ignores undefined variable without underscored param in source" do
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
    refute FixUnderscoredFnParamBindingForBodyUse.match?(diag)
    File.rm(path)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: @real_message, position: {3, 11}, file: "unused"}
    refute FixUnderscoredFnParamBindingForBodyUse.match?(diag)
  end

  test "ignores generic compile error wrapper", %{source_path: path} do
    diag = %{
      severity: :error,
      message:
        "credence_check.ex: cannot compile module M (errors have been logged)",
      position: 0,
      file: path
    }

    refute FixUnderscoredFnParamBindingForBodyUse.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {3, 11}, file: "unused"}

    assert FixUnderscoredFnParamBindingForBodyUse.to_issue(diag).rule ==
             :fix_underscored_fn_param_binding_for_body_use
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {126, 11}, file: "unused"}
    assert FixUnderscoredFnParamBindingForBodyUse.to_issue(diag).meta.line == 126
  end
end
