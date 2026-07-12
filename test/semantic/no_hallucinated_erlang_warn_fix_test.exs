defmodule Credence.Semantic.NoHallucinatedErlangWarnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedErlangWarn

  @real_message ":erlang.warn/1 is undefined or private"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedErlangWarn.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces :erlang.warn with Logger.warning" do
    input = """
    defmodule Example do
      require Logger

      def log_warning(msg) do
        try do
          msg
        rescue
          e ->
            result = :erlang.warn("caught: \#{inspect(e)}")
            result
        end
      end
    end
    """

    expected = """
    defmodule Example do
      require Logger

      def log_warning(msg) do
        try do
          msg
        rescue
          e ->
            result = Logger.warning("caught: \#{inspect(e)}")
            result
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 9), expected)
  end

  test "replaces :erlang.warn in a simple expression" do
    input = """
    defmodule WarnExample do
      require Logger

      def warn(msg) do
        :erlang.warn(msg)
      end
    end
    """

    expected = """
    defmodule WarnExample do
      require Logger

      def warn(msg) do
        Logger.warning(msg)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 5), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule X do
      require Logger

      def f(msg), do: :erlang.warn(msg)
    end
    """

    assert valid_syntax?(fix(input, @real_message, 4))
  end

  test "returns source unchanged when no :erlang.warn present" do
    input = """
    defmodule CleanExample do
      require Logger

      def warn(msg), do: Logger.warning(msg)
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
