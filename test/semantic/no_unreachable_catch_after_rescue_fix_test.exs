defmodule Credence.Semantic.NoUnreachableCatchAfterRescueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnreachableCatchAfterRescue

  @real_message "this catch clause cannot match because a rescue catch-all already handles it"

  defp fix(source, message, line \\ 1) do
    NoUnreachableCatchAfterRescue.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "removes unreachable catch clause after rescue catch-all" do
    input = """
    defmodule M do
      def run do
        try do
          :ok
        rescue
          e -> {:error, e}
        catch
          :error, reason -> {:error, reason}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        try do
          :ok
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def run do
        try do
          :ok
        rescue
          e -> {:error, e}
        catch
          :error, reason -> {:error, reason}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no catch block exists" do
    input = """
    defmodule M do
      def run do
        try do
          :ok
        rescue
          e -> {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged when rescue is not a catch-all" do
    input = """
    defmodule M do
      def run do
        try do
          :ok
        rescue
          e in RuntimeError -> {:error, e}
        catch
          :error, reason -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "removes only :error catch clauses, keeps :exit and :throw" do
    input = """
    defmodule M do
      def run do
        try do
          :ok
        rescue
          e -> {:error, e}
        catch
          :error, reason -> {:error, reason}
          :exit, reason -> {:exit, reason}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        try do
          :ok
        rescue
          e -> {:error, e}
        catch
          :exit, reason -> {:exit, reason}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end
end
