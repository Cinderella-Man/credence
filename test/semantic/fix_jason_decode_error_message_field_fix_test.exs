defmodule Credence.Semantic.FixJasonDecodeErrorMessageFieldFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixJasonDecodeErrorMessageField

  @real_message "unknown key :message for struct Jason.DecodeError"

  defp fix(source, message \\ @real_message, line \\ 1) do
    FixJasonDecodeErrorMessageField.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes interpolated use, keeping the struct match" do
    input = ~S"""
    defmodule TestModule do
      def parse_json(content) do
        case Jason.decode(content) do
          {:ok, _} -> :ok
          {:error, %Jason.DecodeError{message: msg}} -> {:error, "Invalid JSON: #{msg}"}
        end
      end
    end
    """

    expected = ~S"""
    defmodule TestModule do
      def parse_json(content) do
        case Jason.decode(content) do
          {:ok, _} ->
            :ok

          {:error, %Jason.DecodeError{} = error} ->
            {:error, "Invalid JSON: #{Exception.message(error)}"}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule TestModule do
      def parse_json(content) do
        case Jason.decode(content) do
          {:ok, _} -> :ok
          {:error, %Jason.DecodeError{message: msg}} -> {:error, "Invalid JSON: #{msg}"}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fixes direct variable reference in body" do
    input = ~S"""
    defmodule TestModule do
      def parse_json(content) do
        case Jason.decode(content) do
          {:ok, _} -> :ok
          {:error, %Jason.DecodeError{message: msg}} -> {:error, msg}
        end
      end
    end
    """

    expected = ~S"""
    defmodule TestModule do
      def parse_json(content) do
        case Jason.decode(content) do
          {:ok, _} -> :ok
          {:error, %Jason.DecodeError{} = error} -> {:error, Exception.message(error)}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes a pattern using an alias for Jason.DecodeError" do
    input = ~S"""
    defmodule AliasedJasonDecodeError do
      alias Jason.DecodeError

      def f(x) do
        case x do
          %DecodeError{message: msg} -> msg
        end
      end
    end
    """

    expected = ~S"""
    defmodule AliasedJasonDecodeError do
      alias Jason.DecodeError

      def f(x) do
        case x do
          %DecodeError{} = error -> Exception.message(error)
        end
      end
    end
    """

    actual = fix(input)

    confirm_fix(actual, expected)
    assert {:ok, _} = RuleHelpers.compile_and_capture(actual)
    assert {:ok, _} = RuleHelpers.compile_and_capture(expected)
  end

  test "does not replace the message variable inside quoted code" do
    input = ~S"""
    defmodule QuotedJasonDecodeErrorMessage do
      def f(x) do
        case x do
          %Jason.DecodeError{message: msg} -> quote(do: msg)
        end
      end
    end
    """

    expected = ~S"""
    defmodule QuotedJasonDecodeErrorMessage do
      def f(x) do
        case x do
          %Jason.DecodeError{} -> quote(do: msg)
        end
      end
    end
    """

    actual = fix(input)

    confirm_fix(actual, expected)
    assert {:ok, _} = RuleHelpers.compile_and_capture(actual)
    assert {:ok, _} = RuleHelpers.compile_and_capture(expected)
  end

  test "fixes a clause whose guard does not use the message var" do
    input = ~S"""
    defmodule M do
      def f(x, flag) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: msg}} when flag -> msg
        end
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def f(x, flag) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{} = error} when flag -> Exception.message(error)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes every erroneous clause in the file" do
    input = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:ok, v} -> v
          {:error, %Jason.DecodeError{message: msg}} -> msg
        end
      end

      def g(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: m}} -> {:bad, m}
          other -> other
        end
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:ok, v} -> v
          {:error, %Jason.DecodeError{} = error} -> Exception.message(error)
        end
      end

      def g(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{} = error} -> {:bad, Exception.message(error)}
          other -> other
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "drops the entry without binding when the message var is unused" do
    input = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: _msg}} -> :bad_json
        end
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{}} -> :bad_json
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes a message var itself named error" do
    input = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: error}} -> error
        end
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{} = error} -> Exception.message(error)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "returns source unchanged when no Jason.DecodeError pattern" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule ParseHelper do
      def parse(data) do
        case Jason.decode(data) do
          {:ok, result} -> result
          {:error, _} -> nil
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the guard uses the message var" do
    input = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: msg}} when is_binary(msg) -> msg
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the struct has entries besides message" do
    input = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: msg, data: d}} -> {msg, d}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the message value is a literal, not a var" do
    input = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: "unexpected end of input"}} -> :eof
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the var is rebound in the body" do
    input = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: msg}} ->
            msg = String.trim(msg)
            msg
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when a nested fn rebinds the var" do
    input = ~S"""
    defmodule M do
      def f(x, list) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: msg}} -> Enum.map(list, fn msg -> msg end)
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when a variable named error is already in scope" do
    input = ~S"""
    defmodule M do
      def f(x, error) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: msg}} -> {msg, error}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the var also appears elsewhere in the pattern" do
    input = ~S"""
    defmodule M do
      def f(x) do
        case Jason.decode(x) do
          {:error, %Jason.DecodeError{message: msg}, msg} -> msg
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op for a struct pattern in a def head (no clause arrow)" do
    input = ~S"""
    defmodule M do
      def f(%Jason.DecodeError{message: msg}), do: msg
    end
    """

    confirm_fix(fix(input), input)
  end
end
