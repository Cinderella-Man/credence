defmodule Credence.Semantic.PreferRescueBeforeCatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferRescueBeforeCatch

  @message "\"catch\" should always come after \"rescue\" in try"

  defp fix(source, line \\ 1) do
    PreferRescueBeforeCatch.fix(source, %{
      severity: :warning,
      message: @message,
      position: {line, 1}
    })
  end

  test "reorders catch before rescue to rescue before catch" do
    input = ~S"""
    defmodule PreferRescueBeforeCatch do
      def run(fn_or_val) do
        result =
          try do
            {:ok, fn_or_val.()}
          catch
            :exit, reason ->
              {:error, %{kind: :exit, reason: reason}}

            :throw, value ->
              {:error, %{kind: :throw, reason: value}}
          rescue
            e ->
              {:error, %{kind: :error, reason: Exception.message(e)}}
          end

        result
      end
    end
    """

    expected = ~S"""
    defmodule PreferRescueBeforeCatch do
      def run(fn_or_val) do
        result =
          try do
            {:ok, fn_or_val.()}
          rescue
            e ->
              {:error, %{kind: :error, reason: Exception.message(e)}}
          catch
            :exit, reason ->
              {:error, %{kind: :exit, reason: reason}}

            :throw, value ->
              {:error, %{kind: :throw, reason: value}}
          end

        result
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not change source where rescue already precedes catch" do
    input = ~S"""
    defmodule AlreadyCorrect do
      def run(fn_or_val) do
        try do
          {:ok, fn_or_val.()}
        rescue
          e ->
            {:error, Exception.message(e)}
        catch
          :exit, reason ->
            {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule X do
      def run(fn_or_val) do
        try do
          {:ok, fn_or_val.()}
        catch
          :exit, reason ->
            {:error, reason}
        rescue
          e ->
            {:error, Exception.message(e)}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
