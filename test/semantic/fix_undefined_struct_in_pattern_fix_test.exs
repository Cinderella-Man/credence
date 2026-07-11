defmodule Credence.Semantic.FixUndefinedStructInPatternFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUndefinedStructInPattern

  @exit_message "Exit.__struct__/1 is undefined, cannot expand struct Exit"
  @throw_message "ThrowError.__struct__/1 is undefined, cannot expand struct ThrowError"

  defp fix(source, message, line \\ 1) do
    FixUndefinedStructInPattern.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces Exit struct with variable in catch clause" do
    input = """
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

    expected = """
    defmodule Dedup do
      defp execute_func(func) do
        try do
          func.()
        rescue
          e in Exception ->
            {:error, {:exception, e}}
        catch
          :exit, reason ->
            {:error, {:exception, reason}}

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

    confirm_fix(fix(input, @exit_message, 11), expected)
  end

  test "replaces ThrowError struct with variable in catch clause" do
    input = """
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

    expected = """
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
            {:error, {:exception, value}}
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

    confirm_fix(fix(input, @throw_message, 13), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ParseCheck do
      defp execute_func(func) do
        try do
          func.()
        catch
          :exit, reason ->
            {:error, {:exception, %Exit{reason: reason}}}
        end
      end

      defmodule Exit do
        defstruct [:reason]
      end
    end
    """

    assert valid_syntax?(fix(input, @exit_message, 7))
  end

  test "returns source unchanged when struct not in catch clause" do
    input = """
    defmodule Example do
      def build_exit(reason) do
        %Exit{reason: reason}
      end

      defmodule Exit do
        defstruct [:reason]
      end
    end
    """

    result = fix(input, @exit_message, 3)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated diagnostic" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    result = fix(input, "undefined function foo/1", 2)
    confirm_fix(result, input)
  end

  test "returns source unchanged for multi-field struct" do
    input = """
    defmodule Example do
      defp execute_func(func) do
        try do
          func.()
        catch
          :exit, reason ->
            {:error, {:exception, %Exit{reason: reason, code: :crash}}}
        end
      end

      defmodule Exit do
        defstruct [:reason, :code]
      end
    end
    """

    result = fix(input, @exit_message, 7)
    confirm_fix(result, input)
  end

  test "returns source unchanged for struct with non-variable value" do
    input = """
    defmodule Example do
      defp execute_func(func) do
        try do
          func.()
        catch
          :exit, _reason ->
            {:error, {:exception, %Exit{reason: :crash}}}
        end
      end

      defmodule Exit do
        defstruct [:reason]
      end
    end
    """

    result = fix(input, @exit_message, 7)
    confirm_fix(result, input)
  end
end
