defmodule Credence.Syntax.NoRescueOptionInCaseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoRescueOptionInCase

  defp analyze(code), do: NoRescueOptionInCase.analyze(code)
  defp fix(code), do: NoRescueOptionInCase.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule TestModule do
      def analyze(path) do
        case File.stream!(path) do
          {:ok, stream} -> stream
          {:error, reason} -> raise reason
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    expected = """
    defmodule TestModule do
      def analyze(path) do
        try do
          case File.stream!(path) do
            {:ok, stream} -> stream
            {:error, reason} -> raise reason
          end
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("""
           defmodule TestModule do
             def analyze(path) do
               case File.stream!(path) do
                 {:ok, stream} -> stream
                 {:error, reason} -> raise reason
               rescue
                 e -> {:error, e}
               end
             end
           end
           """)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           defmodule TestModule do
             def analyze(path) do
               case File.stream!(path) do
                 {:ok, stream} -> stream
                 {:error, reason} -> raise reason
               rescue
                 e -> {:error, e}
               end
             end
           end
           """))
  end

  test "leaves already-clean source unchanged" do
    input = """
    defmodule TestModule do
      def analyze(path) do
        case File.stream!(path) do
          {:ok, stream} -> stream
          {:error, reason} -> raise reason
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves try-rescue unchanged" do
    input = """
    defmodule TestModule do
      def analyze(path) do
        try do
          case File.stream!(path) do
            {:ok, stream} -> stream
            {:error, reason} -> raise reason
          end
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
