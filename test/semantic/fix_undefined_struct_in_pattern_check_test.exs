defmodule Credence.Semantic.FixUndefinedStructInPatternCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixUndefinedStructInPattern

  @source """
  defmodule Dedup do
    defp execute_func(func) do
      try do
        func.()
      rescue
        e in Exception ->
          {:error, {:exception, e}}
      catch
        :exit, reason ->
          {:error, {:exception, %Exit{reason: reason}}}
        :throw, value ->
          {:error, {:exception, %ThrowError{value: value}}}
      end
    end

    defmodule Exit do
      defstruct [:reason]
    end

    defmodule ThrowError do
      defstruct [:value]
    end
  end
  """

  @exit_message "Exit.__struct__/1 is undefined, cannot expand struct Exit"
  @throw_message "ThrowError.__struct__/1 is undefined, cannot expand struct ThrowError"

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic for Exit struct in catch clause", %{source_path: path} do
    diag = %{severity: :error, message: @exit_message, position: {11, 31}, file: path}
    assert FixUndefinedStructInPattern.match?(diag)
  end

  test "matches the diagnostic for ThrowError struct in catch clause", %{source_path: path} do
    diag = %{severity: :error, message: @throw_message, position: {13, 31}, file: path}
    assert FixUndefinedStructInPattern.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :error, message: "undefined function foo/1", position: {1, 1}, file: path}
    refute FixUndefinedStructInPattern.match?(diag)
  end

  test "ignores warning severity", %{source_path: path} do
    diag = %{severity: :warning, message: @exit_message, position: {11, 31}, file: path}
    refute FixUndefinedStructInPattern.match?(diag)
  end

  test "ignores struct not in catch clause" do
    source = """
    defmodule Example do
      def build_exit(reason) do
        %Exit{reason: reason}
      end

      defmodule Exit do
        defstruct [:reason]
      end
    end
    """

    path =
      Path.join(System.tmp_dir!(), "credence_no_match_#{System.unique_integer([:positive])}.ex")

    File.write!(path, source)
    diag = %{severity: :error, message: @exit_message, position: {3, 9}, file: path}
    refute FixUndefinedStructInPattern.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule", %{source_path: path} do
    diag = %{severity: :error, message: @exit_message, position: {11, 31}, file: path}

    assert FixUndefinedStructInPattern.to_issue(diag).rule ==
             :fix_undefined_struct_in_pattern
  end

  test "sets the line in issue meta" do
    diag = %{severity: :error, message: @exit_message, position: {42, 5}, file: "unused"}
    assert FixUndefinedStructInPattern.to_issue(diag).meta.line == 42
  end
end
