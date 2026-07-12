defmodule Credence.Semantic.FixUndefinedVariableInWithElseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUndefinedVariableInWithElse

  defp fix(source, message, line \\ 1) do
    FixUndefinedVariableInWithElse.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "extracts assignment from with body to before with" do
    input = ~S"""
    defmodule WithElseScopeBug do
      def verify(header, now, tolerance) do
        with true <- header != "",
             sigs = String.split(header, ","),
             true <- sigs != [] do
          {:ok, :verified}
        else
          _ ->
            cond do
              header == "" -> {:error, :invalid}
              sigs == [] -> {:error, :malformed}
              true -> {:error, :expired}
            end
        end
      end
    end
    """

    expected = ~S"""
    defmodule WithElseScopeBug do
      def verify(header, now, tolerance) do
        sigs = String.split(header, ",")

        with true <- header != "",
             true <- sigs != [] do
          {:ok, :verified}
        else
          _ ->
            cond do
              header == "" -> {:error, :invalid}
              sigs == [] -> {:error, :malformed}
              true -> {:error, :expired}
            end
        end
      end
    end
    """

    message = ~s(undefined variable "sigs")
    confirm_fix(fix(input, message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule WithElseScopeBug do
      def verify(header, now, tolerance) do
        with true <- header != "",
             sigs = String.split(header, ","),
             true <- sigs != [] do
          {:ok, :verified}
        else
          _ ->
            sigs
        end
      end
    end
    """

    message = ~s(undefined variable "sigs")
    assert valid_syntax?(fix(input, message))
  end

  test "no-op when no assignment in with body" do
    input = ~S"""
    defmodule Clean do
      def check(header) do
        with true <- header != "",
             true <- header != "x" do
          :ok
        else
          _ -> :error
        end
      end
    end
    """

    message = ~s(undefined variable "other")
    result = fix(input, message)
    confirm_fix(result, input)
  end
end
