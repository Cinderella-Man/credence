defmodule Credence.Semantic.FixUndefinedUnderscoredBindingCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUndefinedUnderscoredBinding

  @source """
  defmodule M do
    defp collect_overlapping(node, {q_start, _q_finish} = query, acc) do
      {start, finish} = node.interval
      if overlaps?(start, finish, q_start, q_finish) do
        [node.interval | acc]
      else
        acc
      end
    end

    defp overlaps?(s1, f1, s2, f2), do: s1 <= f2 and s2 <= f1
  end
  """

  @real_message "undefined variable \"q_finish\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic when source has underscore binding", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {4, 33}, file: path}
    assert FixUndefinedUnderscoredBinding.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}, file: path}
    refute FixUndefinedUnderscoredBinding.match?(diag)
  end

  test "ignores undefined variable without underscore binding in source" do
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
    refute FixUndefinedUnderscoredBinding.match?(diag)
    File.rm(path)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: @real_message, position: {4, 33}, file: "unused"}
    refute FixUndefinedUnderscoredBinding.match?(diag)
  end

  test "ignores generic compile error wrapper", %{source_path: path} do
    diag = %{
      severity: :error,
      message:
        "credence_check.ex: cannot compile module M (errors have been logged)",
      position: 0,
      file: path
    }

    refute FixUndefinedUnderscoredBinding.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {4, 33}, file: "unused"}

    assert FixUndefinedUnderscoredBinding.to_issue(diag).rule ==
             :fix_undefined_underscored_binding
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {10, 9}, file: "unused"}
    assert FixUndefinedUnderscoredBinding.to_issue(diag).meta.line == 10
  end
end
