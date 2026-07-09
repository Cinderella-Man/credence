defmodule Credence.Semantic.NoStructUpdateOnUntypedVariableCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoStructUpdateOnUntypedVariable

  @source """
  defmodule Saga do
    defstruct steps: []

    def execute(context, action_fn)
        when is_function(action_fn, 1) do
      %__MODULE__{
        context
        | steps: context.steps ++ [%{type: :compensable, action: action_fn}]
      }
    end
  end
  """

  @real_message "undefined variable \"context\""

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic", %{source_path: path} do
    diag = %{severity: :error, message: @real_message, position: {5, 5}, file: path}
    assert NoStructUpdateOnUntypedVariable.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "undefined function foo/1", position: {1, 1}, file: path}
    refute NoStructUpdateOnUntypedVariable.match?(diag)
  end

  test "ignores warnings", %{source_path: path} do
    diag = %{severity: :warning, message: @real_message, position: {5, 5}, file: path}
    refute NoStructUpdateOnUntypedVariable.match?(diag)
  end

  test "ignores undefined variable not in struct update pattern" do
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
    refute NoStructUpdateOnUntypedVariable.match?(diag)
    File.rm(path)
  end

  test "ignores undefined variable that is not a function parameter" do
    source = """
    defmodule Example do
      defstruct [:value]

      def test do
        %__MODULE__{x | value: 1}
      end
    end
    """

    path =
      Path.join(System.tmp_dir!(), "credence_no_match2_#{System.unique_integer([:positive])}.ex")

    File.write!(path, source)

    diag = %{severity: :error, message: "undefined variable \"x\"", position: {5, 19}, file: path}
    refute NoStructUpdateOnUntypedVariable.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @real_message, position: {5, 5}, file: "unused"}

    assert NoStructUpdateOnUntypedVariable.to_issue(diag).rule ==
             :no_struct_update_on_untyped_variable
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @real_message, position: {10, 5}, file: "unused"}
    assert NoStructUpdateOnUntypedVariable.to_issue(diag).meta.line == 10
  end

  test "ignores generic compile error wrapper", %{source_path: path} do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module Saga (errors have been logged)",
      position: 0,
      file: path
    }

    refute NoStructUpdateOnUntypedVariable.match?(diag)
  end
end
