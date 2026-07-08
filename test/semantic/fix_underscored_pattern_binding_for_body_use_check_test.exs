defmodule Credence.Semantic.FixUnderscoredPatternBindingForBodyUseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUnderscoredPatternBindingForBodyUse

  @source """
  defmodule UnderscorePatternBindingBug do
    def handle(data) do
      case data do
        {key, _value} ->
          {key, value}
      end
    end
  end
  """

  @real_message "undefined variable \"value\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic when source has underscore binding", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {5, 9}, file: path}
    assert FixUnderscoredPatternBindingForBodyUse.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}, file: path}
    refute FixUnderscoredPatternBindingForBodyUse.match?(diag)
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
    refute FixUnderscoredPatternBindingForBodyUse.match?(diag)
    File.rm(path)
  end

  test "ignores warnings" do
    diag = %{severity: :warning, message: @real_message, position: {5, 9}, file: "unused"}
    refute FixUnderscoredPatternBindingForBodyUse.match?(diag)
  end

  test "ignores generic compile error wrapper", %{source_path: path} do
    diag = %{
      severity: :error,
      message:
        "credence_check.ex: cannot compile module UnderscorePatternBindingBug (errors have been logged)",
      position: 0,
      file: path
    }

    refute FixUnderscoredPatternBindingForBodyUse.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {5, 9}, file: "unused"}

    assert FixUnderscoredPatternBindingForBodyUse.to_issue(diag).rule ==
             :fix_underscored_pattern_binding_for_body_use
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {10, 9}, file: "unused"}
    assert FixUnderscoredPatternBindingForBodyUse.to_issue(diag).meta.line == 10
  end
end
