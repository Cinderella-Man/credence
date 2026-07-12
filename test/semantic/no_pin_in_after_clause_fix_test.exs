defmodule Credence.Semantic.NoPinInAfterClauseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoPinInAfterClause

  @message "misplaced operator ^timeout_ms\n\nThe pin operator ^ is supported only inside matches or inside custom macros. Make sure you are inside a match or all necessary macros have been required"

  defp fix(source, message \\ @message, line \\ 7) do
    NoPinInAfterClause.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "strips pin operator from after clause" do
    input = """
    defmodule PinInAfterExample do
      def wait(timeout_ms) do
        receive do
          {:msg, data} ->
            {:ok, data}
        after
          ^timeout_ms ->
            :timeout
        end
      end
    end
    """

    expected = """
    defmodule PinInAfterExample do
      def wait(timeout_ms) do
        receive do
          {:msg, data} ->
            {:ok, data}
        after
          timeout_ms ->
            :timeout
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "strips pin operator with short variable name" do
    input = """
    defmodule Simple do
      def wait(t) do
        receive do
          :ok -> :ok
        after
          ^t -> :timeout
        end
      end
    end
    """

    expected = """
    defmodule Simple do
      def wait(t) do
        receive do
          :ok -> :ok
        after
          t -> :timeout
        end
      end
    end
    """

    confirm_fix(fix(input, "misplaced operator ^t", 6), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Simple do
      def wait(t) do
        receive do
          :ok -> :ok
        after
          ^t -> :timeout
        end
      end
    end
    """

    assert valid_syntax?(fix(input, "misplaced operator ^t", 6))
  end

  test "returns source unchanged when no pin on target line" do
    input = """
    defmodule Simple do
      def wait(t) do
        receive do
          :ok -> :ok
        after
          t -> :timeout
        end
      end
    end
    """

    confirm_fix(fix(input, "misplaced operator ^t", 6), input)
  end
end
