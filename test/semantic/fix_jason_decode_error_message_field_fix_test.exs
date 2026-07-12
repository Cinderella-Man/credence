defmodule Credence.Semantic.FixJasonDecodeErrorMessageFieldFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixJasonDecodeErrorMessageField

  @real_message "unknown key :message for struct Jason.DecodeError"

  defp fix(source, message, line \\ 1) do
    FixJasonDecodeErrorMessageField.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source by replacing struct pattern with Exception.message" do
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
          {:ok, _} -> :ok
          {:error, error} -> {:error, "Invalid JSON: #{Exception.message(error)}"}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 5), expected)
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

    assert valid_syntax?(fix(input, @real_message, 5))
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
          {:error, error} -> {:error, Exception.message(error)}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 5), expected)
  end

  test "returns source unchanged when no Jason.DecodeError pattern" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
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

    confirm_fix(fix(input, @real_message), input)
  end
end
